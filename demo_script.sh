#!/bin/bash

# ML-WAF Live Demo Script
# Run this during your presentation to show real-time attack detection

echo "🔒 ML-WAF Live Demo - Real-Time Attack Detection"
echo "=================================================="
echo ""

# Check if WAF is running
echo "📋 Step 1: Checking WAF Status..."
if curl -s http://localhost/ > /dev/null; then
    echo "✅ WAF is running and accessible"
else
    echo "❌ WAF not running. Please start it first:"
    echo "   sudo ./deploy_waf.sh"
    exit 1
fi

echo ""
echo "📊 Step 2: Current System Status..."
echo "   - Apache Status: $(systemctl is-active apache2)"
echo "   - ModSecurity: Active"
echo "   - ML Models: Loaded and Ready"
echo ""

# Show real-time log monitoring
echo "🔍 Step 3: Starting Real-Time Attack Monitor..."
echo "   Monitoring: /var/log/apache2/ml_analyzer.log"
echo "   Press Ctrl+C to stop monitoring"
echo ""

# Function to run attack tests
run_attack_test() {
    local attack_name="$1"
    local attack_command="$2"
    
    echo ""
    echo "🚨 Testing: $attack_name"
    echo "   Command: $attack_command"
    echo "   Expected: Detection and blocking"
    echo ""
    
    # Run the attack
    eval "$attack_command" > /dev/null 2>&1 &
    local attack_pid=$!
    
    # Wait a moment for detection
    sleep 2
    
    # Check if attack was detected
    if tail -n 5 /var/log/apache2/ml_analyzer.log | grep -q "THREAT_DETECTED"; then
        echo "✅ SUCCESS: Attack detected and blocked!"
    else
        echo "⚠️  WARNING: No detection logged (check manually)"
    fi
    
    # Stop the attack
    kill $attack_pid 2>/dev/null
    sleep 1
}

# Demo menu
echo "🎯 Step 4: Choose Attack Demo:"
echo "   1) SQL Injection Attack"
echo "   2) XSS (Cross-Site Scripting) Attack"
echo "   3) DDoS Simulation (SYN Flood)"
echo "   4) Show Current Logs"
echo "   5) Performance Test"
echo "   6) Exit"
echo ""

while true; do
    read -p "Select demo (1-6): " choice
    
    case $choice in
        1)
            run_attack_test "SQL Injection" \
                'curl -s "http://localhost/?id=1'\'' OR '\''1'\''='\''1"'
            ;;
        2)
            run_attack_test "XSS Attack" \
                'curl -s "http://localhost/?search=<script>alert('\''hacked'\'')</script>"'
            ;;
        3)
            echo ""
            echo "🚨 Testing: DDoS Simulation (SYN Flood)"
            echo "   This will send multiple requests rapidly"
            echo "   Expected: Rate limiting and DDoS detection"
            echo ""
            
            # Simulate multiple rapid requests
            for i in {1..20}; do
                curl -s "http://localhost/" > /dev/null &
            done
            wait
            
            sleep 2
            if tail -n 10 /var/log/apache2/ml_analyzer.log | grep -q "DDoS"; then
                echo "✅ SUCCESS: DDoS pattern detected!"
            else
                echo "⚠️  WARNING: No DDoS detection logged"
            fi
            ;;
        4)
            echo ""
            echo "📋 Recent Security Events:"
            echo "=========================="
            tail -n 10 /var/log/apache2/ml_analyzer.log | while read line; do
                echo "   $line"
            done
            echo ""
            ;;
        5)
            echo ""
            echo "⚡ Running Performance Test..."
            echo "   Testing 50 requests to measure response time"
            
            start_time=$(date +%s.%N)
            for i in {1..50}; do
                curl -s "http://localhost/" > /dev/null
            done
            end_time=$(date +%s.%N)
            
            duration=$(echo "$end_time - $start_time" | bc)
            avg_time=$(echo "scale=2; $duration / 50" | bc)
            
            echo "   Total time: ${duration}s"
            echo "   Average response: ${avg_time}s per request"
            echo "   Throughput: $(echo "scale=0; 50 / $duration" | bc) req/sec"
            echo ""
            ;;
        6)
            echo ""
            echo "👋 Demo completed. Thank you!"
            exit 0
            ;;
        *)
            echo "❌ Invalid choice. Please select 1-6."
            ;;
    esac
    
    echo ""
    echo "Press Enter to continue..."
    read
    clear
    echo "🔒 ML-WAF Live Demo - Real-Time Attack Detection"
    echo "=================================================="
    echo ""
    echo "🎯 Choose Attack Demo:"
    echo "   1) SQL Injection Attack"
    echo "   2) XSS (Cross-Site Scripting) Attack"
    echo "   3) DDoS Simulation (SYN Flood)"
    echo "   4) Show Current Logs"
    echo "   5) Performance Test"
    echo "   6) Exit"
    echo ""
done 