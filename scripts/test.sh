#!/bin/bash

# Test script for infra-seed services
# Tests both GCP load balancer IP directly and Cloudflare domain endpoints

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DOMAIN="hundred.sh"
SERVICES=("one" "two" "three")
TIMEOUT=10

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "INFO")
            echo -e "${BLUE}$message${NC}"
            ;;
        "SUCCESS")
            echo -e "${GREEN}$message${NC}"
            ;;
        "ERROR")
            echo -e "${RED}$message${NC}"
            ;;
        "WARNING")
            echo -e "${YELLOW}$message${NC}"
            ;;
    esac
}

# Function to test HTTP endpoint
test_endpoint() {
    local url=$1
    local description=$2
    local host_header=${3:-""}
    
    # Build curl command for display
    local curl_display="curl"
    if [[ -n "$host_header" ]]; then
        curl_display="$curl_display -k -H 'Host: $host_header'"
    fi
    curl_display="$curl_display '$url'"
    
    # Test with timeout and get both status code and response
    local response
    if [[ -n "$host_header" ]]; then
        # For direct IP with Host header, skip SSL verification (certificate won't match IP)
        response=$(curl -k -s -w "HTTPSTATUS:%{http_code}" --connect-timeout $TIMEOUT --max-time $TIMEOUT -H "Host: $host_header" "$url" 2>/dev/null || echo "HTTPSTATUS:000")
    else
        response=$(curl -s -w "HTTPSTATUS:%{http_code}" --connect-timeout $TIMEOUT --max-time $TIMEOUT "$url" 2>/dev/null || echo "HTTPSTATUS:000")
    fi
    
    local body=$(echo "$response" | sed -E 's/HTTPSTATUS\:[0-9]{3}$//')
    local status_code=$(echo "$response" | tr -d '\n' | sed -E 's/.*HTTPSTATUS:([0-9]{3})$/\1/')
    
    # Truncate body for display (first 80 chars)
    local display_body=$(echo "$body" | tr -d '\n' | cut -c1-80)
    if [[ ${#body} -gt 80 ]]; then
        display_body="${display_body}..."
    fi
    
    # Use wider format for commands with Host header (load balancer tests)
    local format_width=50
    if [[ -n "$host_header" ]]; then
        format_width=70
    fi
    
    if [[ "$status_code" == "200" ]]; then
        printf "${GREEN}✅${NC} %-${format_width}s → HTTP %s | %s\n" "$curl_display" "$status_code" "$display_body"
        return 0
    elif [[ "$status_code" == "000" ]]; then
        printf "${RED}❌${NC} %-${format_width}s → Connection failed\n" "$curl_display"
        return 1
    else
        printf "${RED}❌${NC} %-${format_width}s → HTTP %s | %s\n" "$curl_display" "$status_code" "$display_body"
        return 1
    fi
}

# Function to get GCP load balancer IP
get_gateway_ip() {
    # Try to get the Gateway IP from kubectl
    local gateway_ip=$(kubectl get gateway infra-seed-main-gateway -n default -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")
    
    if [[ -n "$gateway_ip" ]]; then
        echo "$gateway_ip"
    else
        return 1
    fi
}

# Function to test GCP load balancer directly
test_gcp_load_balancer() {
    print_status "INFO" "=== Testing GCP Load Balancer Direct IP (Using -k flag to skip SSL verification) ==="

    local gateway_ip
    gateway_ip=$(get_gateway_ip) || {
        print_status "ERROR" "Could not retrieve Gateway IP. Make sure kubectl is configured and Gateway is deployed."
        return 1
    }
    
    local passed=0
    local failed=0
    
    # Test each service endpoint on the direct IP
    for service in "${SERVICES[@]}"; do
        local url="https://$gateway_ip/$service"
        if test_endpoint "$url" "Service $service (direct IP)" "$DOMAIN"; then
            ((passed++))
        else
            ((failed++))
        fi
        
        # Test health endpoint if available
        local health_url="https://$gateway_ip/$service/health"
        if test_endpoint "$health_url" "Service $service health (direct IP)" "$DOMAIN"; then
            ((passed++))
        else
            ((failed++))
        fi
    done
    
    echo
    return $([[ $failed -eq 0 ]] && echo 0 || echo 1)
}

# Function to test Cloudflare domain endpoints
test_cloudflare_domain() {
    print_status "INFO" "=== Testing Cloudflare Domain Endpoints ==="
    
    local passed=0
    local failed=0
    
    # Test each service endpoint through Cloudflare
    for service in "${SERVICES[@]}"; do
        local url="https://$DOMAIN/$service"
        if test_endpoint "$url" "Service $service (Cloudflare)"; then
            ((passed++))
        else
            ((failed++))
        fi
        
        # Test health endpoint if available
        local health_url="https://$DOMAIN/$service/health"
        if test_endpoint "$health_url" "Service $service health (Cloudflare)"; then
            ((passed++))
        else
            ((failed++))
        fi
    done

    return $([[ $failed -eq 0 ]] && echo 0 || echo 1)
}

# Function to test DNS resolution
test_dns_resolution() {
    print_status "INFO" "=== Testing DNS Resolution ==="

    # Test domain resolution
    local domain_ips_raw
    domain_ips_raw=$(dig +short "$DOMAIN" @8.8.8.8 2>/dev/null || echo "")
    # Join IPs into a single comma-separated line
    local domain_ips
    domain_ips=$(echo "$domain_ips_raw" | paste -sd, -)
    if [[ -n "$domain_ips" ]]; then
        print_status "SUCCESS" "✅ $DOMAIN resolves to: $domain_ips"
    else
        print_status "ERROR" "❌ Failed to resolve $DOMAIN"
        return 1
    fi

    # Get Gateway IP for comparison
    local gateway_ip
    gateway_ip=$(get_gateway_ip 2>/dev/null) || gateway_ip="unknown"

    if [[ "$domain_ips" == "$gateway_ip" ]]; then
        print_status "SUCCESS" "✅ Domain IP matches Gateway IP"
    else
        print_status "WARNING" "⚠️  Domain IP ($domain_ips) differs from Gateway IP ($gateway_ip)"
        print_status "INFO" "This is expected when using Cloudflare proxy (orange cloud)"
    fi

    echo
}

# Function to check prerequisites
check_prerequisites() {
    print_status "INFO" "=== Checking Prerequisites ==="
    
    local overall_success=true
    
    # Check if kubectl is available
    if command -v kubectl &> /dev/null; then
        printf "${GREEN}✅${NC} kubectl is installed\n"
    else
        printf "${RED}❌${NC} kubectl is not installed or not in PATH\n"
        overall_success=false
    fi
    
    # Check if curl is available
    if command -v curl &> /dev/null; then
        printf "${GREEN}✅${NC} curl is installed\n"
    else
        printf "${RED}❌${NC} curl is not installed or not in PATH\n"
        overall_success=false
    fi
    
    # Check if jq is available (optional, for pretty JSON parsing)
    if command -v jq &> /dev/null; then
        printf "${GREEN}✅${NC} jq is installed (optional)\n"
    else
        printf "${YELLOW}⚠️${NC} jq is not installed - JSON responses will not be parsed\n"
    fi
    
    # Check if dig is available
    if command -v dig &> /dev/null; then
        printf "${GREEN}✅${NC} dig is installed\n"
    else
        printf "${YELLOW}⚠️${NC} dig is not installed - DNS resolution test will be skipped\n"
    fi
    
    # Check kubectl connectivity
    local cluster_info_output
    cluster_info_output=$(kubectl cluster-info 2>&1)
    local cluster_info_exit_code=$?
    
    if [[ $cluster_info_exit_code -eq 0 ]]; then
        printf "${GREEN}✅${NC} kubectl can connect to cluster\n"
    else
        printf "${RED}❌${NC} kubectl cannot connect to cluster\n"
        echo "Error details: $cluster_info_output"
        overall_success=false
    fi
    
    # Check if Gateway exists
    local gateway_check_output
    gateway_check_output=$(kubectl get gateway infra-seed-main-gateway -n default -o name 2>&1)
    local gateway_check_exit_code=$?
    
    if [[ $gateway_check_exit_code -eq 0 ]]; then
        printf "${GREEN}✅${NC} Gateway infra-seed-main-gateway exists\n"
    else
        printf "${RED}❌${NC} Gateway infra-seed-main-gateway not found\n"
        echo "Error details: $gateway_check_output"
        overall_success=false
    fi
    
    # Check if Gateway has an IP address assigned
    local gateway_ip
    gateway_ip=$(get_gateway_ip 2>/dev/null)
    local gateway_ip_exit_code=$?
    
    if [[ $gateway_ip_exit_code -eq 0 && -n "$gateway_ip" ]]; then
        printf "${GREEN}✅${NC} Gateway has IP address assigned: $gateway_ip\n"
    else
        printf "${RED}❌${NC} Gateway does not have an IP address assigned\n"
        echo "Error details: Gateway may still be provisioning or failed to deploy"
        overall_success=false
    fi
    
    echo
    
    if [[ "$overall_success" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Test infra-seed services via GCP load balancer and Cloudflare domain"
    echo ""
    echo "Options:"
    echo "  -g, --gcp-only     Test GCP load balancer only"
    echo "  -c, --cf-only      Test Cloudflare domain only"
    echo "  -d, --dns-only     Test DNS resolution only"
    echo "  -t, --timeout SEC  Set timeout for requests (default: $TIMEOUT)"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                 # Test everything"
    echo "  $0 --gcp-only      # Test GCP load balancer only"
    echo "  $0 --cf-only       # Test Cloudflare domain only"
    echo "  $0 --timeout 5     # Use 5 second timeout"
}

# Main function
main() {
    local test_gcp=true
    local test_cf=true
    local test_dns=true
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -g|--gcp-only)
                test_cf=false
                test_dns=false
                shift
                ;;
            -c|--cf-only)
                test_gcp=false
                test_dns=false
                shift
                ;;
            -d|--dns-only)
                test_gcp=false
                test_cf=false
                shift
                ;;
            -t|--timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_status "ERROR" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    echo "=================================="
    echo "🚀 infra-seed Service Testing Script"
    echo "=================================="
    echo
    
    # Check prerequisites
    if ! check_prerequisites; then
        exit 1
    fi
    
    local overall_result=0
    
    # Run DNS test
    if [[ "$test_dns" == true ]]; then
        if command -v dig &> /dev/null; then
            test_dns_resolution || overall_result=1
        else
            print_status "WARNING" "Skipping DNS test - dig not available"
            echo
        fi
    fi
    
    # Run GCP load balancer test
    if [[ "$test_gcp" == true ]]; then
        test_gcp_load_balancer || overall_result=1
        echo
    fi
    
    # Run Cloudflare domain test
    if [[ "$test_cf" == true ]]; then
        test_cloudflare_domain || overall_result=1
        echo
    fi
    
    # Final summary
    if [[ $overall_result -eq 0 ]]; then
        print_status "SUCCESS" "🎉 All tests passed!"
        exit 0
    else
        print_status "ERROR" "❌ Some tests failed. Check the output above for details."
        
        # Check if we saw "fault filter abort" errors
        if [[ "$test_gcp" == true ]] || [[ "$test_cf" == true ]]; then
            print_status "INFO" ""
            print_status "INFO" "Note: 'fault filter abort' errors are expected during initial Gateway deployment"
            print_status "INFO" "before HTTPRoutes are fully configured. Services should become available once"
            print_status "INFO" "routes are properly configured and health checks pass."
            print_status "INFO" "See: https://cloud.google.com/kubernetes-engine/docs/how-to/deploying-multi-cluster-gateways"
        fi
        
        exit 1
    fi
}

# Run main function with all arguments
main "$@"
