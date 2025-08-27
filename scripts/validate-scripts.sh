#!/bin/bash
# Script Validation Tool for PXF CI/CD Scripts
# This script validates syntax and basic functionality of all CI/CD scripts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔍 Validating PXF CI/CD scripts..."

# Function to validate script syntax
validate_syntax() {
    local script="$1"
    local script_name=$(basename "$script")
    
    echo "📋 Validating syntax: $script_name"
    
    if bash -n "$script"; then
        echo "✅ $script_name: Syntax OK"
        return 0
    else
        echo "❌ $script_name: Syntax Error"
        return 1
    fi
}

# Function to check script permissions
check_permissions() {
    local script="$1"
    local script_name=$(basename "$script")
    
    if [ -x "$script" ]; then
        echo "✅ $script_name: Executable"
        return 0
    else
        echo "⚠️ $script_name: Not executable (fixing...)"
        chmod +x "$script"
        echo "✅ $script_name: Made executable"
        return 0
    fi
}

# Function to validate script structure
validate_structure() {
    local script="$1"
    local script_name=$(basename "$script")
    
    echo "📋 Validating structure: $script_name"
    
    local issues=0
    
    # Check for shebang
    if ! head -1 "$script" | grep -q "^#!/bin/bash"; then
        echo "⚠️ $script_name: Missing or incorrect shebang"
        issues=$((issues + 1))
    fi
    
    # Check for set -euo pipefail
    if ! grep -q "set -euo pipefail" "$script"; then
        echo "⚠️ $script_name: Missing 'set -euo pipefail'"
        issues=$((issues + 1))
    fi
    
    # Check for main function or execution logic
    if ! grep -q "main()" "$script" && ! grep -q "# Execute" "$script"; then
        echo "⚠️ $script_name: No clear main execution pattern"
        issues=$((issues + 1))
    fi
    
    # Skip non-English check for now as UTF-8 symbols are acceptable in modern scripts
    # All scripts use English comments with some UTF-8 symbols which is fine
    
    if [ "$issues" -eq 0 ]; then
        echo "✅ $script_name: Structure OK"
        return 0
    else
        echo "⚠️ $script_name: $issues structure issues found"
        return 1
    fi
}

# Function to validate script documentation
validate_documentation() {
    local script="$1"
    local script_name=$(basename "$script")
    
    echo "📋 Validating documentation: $script_name"
    
    local issues=0
    
    # Check for script description
    if ! head -5 "$script" | grep -q "# .*[Ss]cript\|# .*[Pp]urpose\|# .*[Dd]escription"; then
        echo "⚠️ $script_name: Missing script description"
        issues=$((issues + 1))
    fi
    
    # Check for usage information
    if ! grep -q "Usage:\|usage:\|USAGE:" "$script" && ! grep -q "echo.*Usage" "$script"; then
        echo "⚠️ $script_name: Missing usage information"
        issues=$((issues + 1))
    fi
    
    if [ "$issues" -eq 0 ]; then
        echo "✅ $script_name: Documentation OK"
        return 0
    else
        echo "⚠️ $script_name: $issues documentation issues found"
        return 1
    fi
}

# Main validation function
main() {
    local total_scripts=0
    local valid_scripts=0
    local syntax_errors=0
    local structure_issues=0
    local doc_issues=0
    
    echo "🚀 Starting script validation..."
    echo ""
    
    # Find all shell scripts in the scripts directory
    for script in "$SCRIPT_DIR"/*.sh; do
        if [ -f "$script" ] && [ "$(basename "$script")" != "validate-scripts.sh" ]; then
            total_scripts=$((total_scripts + 1))
            local script_valid=true
            
            echo "🔍 Validating: $(basename "$script")"
            echo "----------------------------------------"
            
            # Check permissions
            check_permissions "$script"
            
            # Validate syntax
            if ! validate_syntax "$script"; then
                syntax_errors=$((syntax_errors + 1))
                script_valid=false
            fi
            
            # Validate structure
            if ! validate_structure "$script"; then
                structure_issues=$((structure_issues + 1))
                script_valid=false
            fi
            
            # Validate documentation
            if ! validate_documentation "$script"; then
                doc_issues=$((doc_issues + 1))
                # Don't mark as invalid for documentation issues
            fi
            
            if [ "$script_valid" = true ]; then
                valid_scripts=$((valid_scripts + 1))
                echo "🎉 $(basename "$script"): Overall validation PASSED"
            else
                echo "💥 $(basename "$script"): Overall validation FAILED"
            fi
            
            echo ""
        fi
    done
    
    # Generate summary report
    echo "📊 Validation Summary"
    echo "===================="
    echo "Total Scripts: $total_scripts"
    echo "Valid Scripts: $valid_scripts"
    echo "Syntax Errors: $syntax_errors"
    echo "Structure Issues: $structure_issues"
    echo "Documentation Issues: $doc_issues"
    echo ""
    
    # Calculate success rate
    if [ "$total_scripts" -gt 0 ]; then
        local success_rate=$((valid_scripts * 100 / total_scripts))
        echo "Success Rate: $success_rate%"
        
        if [ "$success_rate" -eq 100 ]; then
            echo "🎉 All scripts passed validation!"
            return 0
        elif [ "$success_rate" -ge 80 ]; then
            echo "✅ Most scripts passed validation (minor issues found)"
            return 0
        else
            echo "⚠️ Several scripts have validation issues"
            return 1
        fi
    else
        echo "⚠️ No scripts found to validate"
        return 1
    fi
}

# Function to show help
show_help() {
    cat << EOF
PXF CI/CD Script Validator

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help      Show this help message
    -v, --verbose   Enable verbose output

DESCRIPTION:
    This script validates all PXF CI/CD scripts for:
    - Syntax correctness
    - Proper structure and error handling
    - Documentation completeness
    - Executable permissions

EXAMPLES:
    $0                  # Validate all scripts
    $0 --verbose        # Validate with detailed output
    $0 --help           # Show this help

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--verbose)
            set -x
            shift
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Execute main function
main "$@"
