#!/bin/bash

# ML WAF Analyzer Script
# This script is called by ModSecurity to analyze requests using ML models

# Configuration
ML_SCRIPT="/opt/ml/waf_ml_integration.py"
LOG_FILE="/var/log/apache2/ml_analyzer.log"
PERFORMANCE_LOG="/var/log/apache2/ml_performance.log"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Function to extract request features from ModSecurity variables
extract_request_data() {
    # Extract data from environment variables set by ModSecurity
    local request_data=$(cat << EOF
{
    "uri": "${REQUEST_URI:-/}",
    "query_string": "${QUERY_STRING:-}",
    "user_agent": "${HTTP_USER_AGENT:-}",
    "content_length": ${CONTENT_LENGTH:-0},
    "request_method": "${REQUEST_METHOD:-GET}",
    "remote_addr": "${REMOTE_ADDR:-127.0.0.1}",
    "server_name": "${SERVER_NAME:-localhost}",
    "headers": {
        "host": "${HTTP_HOST:-}",
        "referer": "${HTTP_REFERER:-}",
        "accept": "${HTTP_ACCEPT:-}",
        "accept_language": "${HTTP_ACCEPT_LANGUAGE:-}",
        "accept_encoding": "${HTTP_ACCEPT_ENCODING:-}"
    },
    "connection_count": 1,
    "post_data": ""
}
EOF
)
    echo "$request_data"
}

# Main analysis function
analyze_request() {
    local start_time=$(date +%s.%N)
    
    log_message "Starting ML analysis for ${REQUEST_URI:-unknown}"
    
    # Check if ML script exists
    if [[ ! -f "$ML_SCRIPT" ]]; then
        log_message "ERROR: ML script not found at $ML_SCRIPT"
        echo "ML_BLOCK=1"
        echo "ML_REASON=ml_script_not_found"
        return 1
    fi
    
    # Extract request data
    local request_data=$(extract_request_data)
    log_message "Request data: $request_data"
    
    # Run ML analysis
    local ml_result
    ml_result=$(echo "$request_data" | python3 "$ML_SCRIPT" analyze 2>&1)
    local ml_exit_code=$?
    
    local end_time=$(date +%s.%N)
    local processing_time=$(echo "$end_time - $start_time" | bc -l)
    
    log_message "ML analysis completed in ${processing_time}s with exit code $ml_exit_code"
    log_message "ML result: $ml_result"
    
    # Log performance metrics
    echo "$(date +%s.%N),$processing_time,$ml_exit_code" >> "$PERFORMANCE_LOG"
    
    # Set ModSecurity variables based on result
    if [[ $ml_exit_code -eq 0 ]]; then
        # Request allowed
        echo "ML_BLOCK=0"
        echo "ML_REASON=allowed"
        echo "ML_DDOS_SCORE=0.0"
        echo "ML_SQL_XSS_SCORE=0.0"
        log_message "Request allowed by ML analysis"
    else
        # Request blocked
        echo "ML_BLOCK=1"
        echo "ML_REASON=ml_detected_threat"
        echo "ML_DDOS_SCORE=1.0"
        echo "ML_SQL_XSS_SCORE=1.0"
        log_message "Request blocked by ML analysis"
    fi
    
    return $ml_exit_code
}

# Performance monitoring function
monitor_performance() {
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')
    local memory_usage=$(free | grep Mem | awk '{printf "%.2f", $3/$2 * 100.0}')
    local timestamp=$(date +%s.%N)
    
    echo "$timestamp,$cpu_usage,$memory_usage" >> "/var/log/apache2/system_performance.log"
}

# Main execution
main() {
    # Create log files if they don't exist
    touch "$LOG_FILE" "$PERFORMANCE_LOG"
    
    # Set permissions
    chmod 644 "$LOG_FILE" "$PERFORMANCE_LOG"
    
    log_message "=== ML WAF Analyzer Started ==="
    log_message "Environment: REQUEST_URI=${REQUEST_URI:-}, REMOTE_ADDR=${REMOTE_ADDR:-}, USER_AGENT=${HTTP_USER_AGENT:-}"
    
    # Monitor system performance
    monitor_performance
    
    # Analyze the request
    analyze_request
    local result=$?
    
    log_message "=== ML WAF Analyzer Finished ==="
    
    return $result
}

# Execute main function
main "$@" 