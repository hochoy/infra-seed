#!/bin/bash

# Monitor Gateway and HTTPRoute propagation status
# This script checks the status of the Gateway, HTTPRoutes, and backend services

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Function to check Gateway status
check_gateway_status() {
    print_status "INFO" "=== Gateway Status ==="
    
    # Get Gateway conditions
    local gateway_conditions=$(kubectl get gateway infra-seed-main-gateway -n default -o json 2>/dev/null)
    
    if [[ -z "$gateway_conditions" ]]; then
        print_status "ERROR" "❌ Gateway not found"
        return 1
    fi
    
    # Check Programmed status
    local programmed=$(echo "$gateway_conditions" | jq -r '.status.conditions[] | select(.type=="Programmed") | .status')
    if [[ "$programmed" == "True" ]]; then
        print_status "SUCCESS" "✅ Gateway is Programmed"
    else
        print_status "WARNING" "⚠️  Gateway is not yet Programmed"
    fi
    
    # Check for IP address
    local gateway_ip=$(echo "$gateway_conditions" | jq -r '.status.addresses[0].value // empty')
    if [[ -n "$gateway_ip" ]]; then
        print_status "SUCCESS" "✅ Gateway IP: $gateway_ip"
    else
        print_status "ERROR" "❌ Gateway IP not assigned"
    fi
    
    # Check attached routes
    local attached_routes=$(echo "$gateway_conditions" | jq -r '.status.listeners[0].attachedRoutes // 0')
    print_status "INFO" "📊 Attached Routes: $attached_routes"
    
    echo
}

# Function to check HTTPRoute status
check_httproute_status() {
    print_status "INFO" "=== HTTPRoute Status ==="
    
    local namespaces=("service-one" "service-two" "service-three")
    
    for ns in "${namespaces[@]}"; do
        local route_name="${ns}-route"
        local route_status=$(kubectl get httproute "$route_name" -n "$ns" -o json 2>/dev/null)
        
        if [[ -z "$route_status" ]]; then
            print_status "ERROR" "❌ ${ns}: Route not found"
            continue
        fi
        
        # Check if route is accepted
        local accepted=$(echo "$route_status" | jq -r '.status.parents[0].conditions[] | select(.type=="Accepted") | .status')
        local resolved=$(echo "$route_status" | jq -r '.status.parents[0].conditions[] | select(.type=="ResolvedRefs") | .status')
        
        if [[ "$accepted" == "True" ]] && [[ "$resolved" == "True" ]]; then
            print_status "SUCCESS" "✅ ${ns}: Route configured correctly"
        else
            print_status "WARNING" "⚠️  ${ns}: Route not fully configured (Accepted: $accepted, ResolvedRefs: $resolved)"
        fi
    done
    
    echo
}

# Function to check pod status
check_pod_status() {
    print_status "INFO" "=== Pod Status ==="
    
    local namespaces=("service-one" "service-two" "service-three")
    
    for ns in "${namespaces[@]}"; do
        local pod_count=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l)
        local ready_count=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        
        if [[ $pod_count -eq 0 ]]; then
            print_status "ERROR" "❌ ${ns}: No pods found"
        elif [[ $ready_count -eq $pod_count ]]; then
            print_status "SUCCESS" "✅ ${ns}: All $ready_count/$pod_count pods running"
        else
            print_status "WARNING" "⚠️  ${ns}: Only $ready_count/$pod_count pods running"
        fi
    done
    
    echo
}

# Function to check service NEG status
check_neg_status() {
    print_status "INFO" "=== Network Endpoint Group (NEG) Status ==="
    
    local namespaces=("service-one" "service-two" "service-three")
    
    for ns in "${namespaces[@]}"; do
        local service_name="${ns}-service"
        local neg_status=$(kubectl get service "$service_name" -n "$ns" -o jsonpath='{.metadata.annotations.cloud\.google\.com/neg-status}' 2>/dev/null)
        
        if [[ -n "$neg_status" ]]; then
            local neg_name=$(echo "$neg_status" | jq -r '.network_endpoint_groups."80"' 2>/dev/null)
            if [[ -n "$neg_name" ]] && [[ "$neg_name" != "null" ]]; then
                print_status "SUCCESS" "✅ ${ns}: NEG created ($neg_name)"
            else
                print_status "WARNING" "⚠️  ${ns}: NEG status available but not fully configured"
            fi
        else
            print_status "WARNING" "⚠️  ${ns}: NEG not created yet"
        fi
    done
    
    echo
}

# Function to check backend service health
check_backend_health() {
    print_status "INFO" "=== Backend Service Health ==="
    
    # Get backend services related to the gateway
    local backend_services=$(gcloud compute backend-services list --filter="name~gkegw1" --format="value(name)" 2>/dev/null)
    
    if [[ -z "$backend_services" ]]; then
        print_status "WARNING" "⚠️  No backend services found yet (this is normal during initial setup)"
        echo
        return
    fi
    
    while IFS= read -r backend_service; do
        if [[ -z "$backend_service" ]]; then
            continue
        fi
        
        # Get health status
        local health_status=$(gcloud compute backend-services get-health "$backend_service" --global --format="json" 2>/dev/null)
        
        if [[ -n "$health_status" ]] && [[ "$health_status" != "[]" ]]; then
            local healthy_count=$(echo "$health_status" | jq '[.[]? | .status.healthStatus[]? | select(.healthState=="HEALTHY")] | length' 2>/dev/null || echo "0")
            local total_count=$(echo "$health_status" | jq '[.[]? | .status.healthStatus[]?] | length' 2>/dev/null || echo "0")
            
            if [[ $healthy_count -gt 0 ]]; then
                print_status "SUCCESS" "✅ Backend: ${backend_service} ($healthy_count/$total_count healthy)"
            elif [[ $total_count -gt 0 ]]; then
                print_status "WARNING" "⚠️  Backend: ${backend_service} ($healthy_count/$total_count healthy)"
            else
                print_status "INFO" "ℹ️  Backend: ${backend_service} (no endpoints yet)"
            fi
        else
            print_status "INFO" "ℹ️  Backend: ${backend_service} (checking...)"
        fi
    done <<< "$backend_services"
    
    echo
}

# Function to show recent Gateway events
show_gateway_events() {
    print_status "INFO" "=== Recent Gateway Events ==="
    
    kubectl get events -n default --field-selector involvedObject.name=infra-seed-main-gateway --sort-by='.lastTimestamp' 2>/dev/null | tail -5
    
    echo
}

# Function to provide summary and recommendations
show_summary() {
    print_status "INFO" "=== Summary ==="
    
    # Check if everything looks good
    local gateway_ready=$(kubectl get gateway infra-seed-main-gateway -n default -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null)
    local routes_configured=true
    
    for ns in service-one service-two service-three; do
        local route_accepted=$(kubectl get httproute "${ns}-route" -n "$ns" -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}' 2>/dev/null)
        if [[ "$route_accepted" != "True" ]]; then
            routes_configured=false
        fi
    done
    
    if [[ "$gateway_ready" == "True" ]] && [[ "$routes_configured" == true ]]; then
        print_status "SUCCESS" "🎉 Gateway and routes are fully configured!"
        print_status "INFO" "Run './scripts/test.sh' to verify endpoint availability"
    else
        print_status "WARNING" "⏳ Gateway is still propagating changes..."
        print_status "INFO" "This typically takes 2-5 minutes. Run this script again to check progress."
        print_status "INFO" "Or run: watch -n 10 ./scripts/monitor.sh"
    fi
    
    echo
}

# Main function
main() {
    echo "========================================="
    echo "🔍 Gateway Propagation Monitor"
    echo "========================================="
    echo
    
    check_gateway_status
    check_httproute_status
    check_pod_status
    check_neg_status
    check_backend_health
    show_gateway_events
    show_summary
}

# Run main function
main "$@"
