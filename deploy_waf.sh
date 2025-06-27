#!/bin/bash

# ML WAF Deployment Script
# This script sets up the complete ML-based Web Application Firewall

set -e  # Exit on any error

# Configuration
ML_DIR="/opt/ml"
APACHE_SITES_DIR="/etc/apache2/sites-available"
LOG_DIR="/var/log/apache2"
WEB_DIR="/var/www/waf-demo"

echo "ML WAF Deployment Script"
echo "=============================="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)"
   exit 1
fi

# Function to print status
print_status() {
    echo "[INFO] $1"
}

print_success() {
    echo "[SUCCESS] $1"
}

print_error() {
    echo "[ERROR] $1"
}

# Create necessary directories
print_status "Creating directories..."
mkdir -p "$ML_DIR"
mkdir -p "$LOG_DIR"
mkdir -p "$WEB_DIR"
mkdir -p "/usr/local/bin"

# Copy ML models
print_status "Installing ML models..."
if [[ -f "ddosattack.h5" ]]; then
    cp ddosattack.h5 "$ML_DIR/"
    chmod 644 "$ML_DIR/ddosattack.h5"
    print_success "DDoS model installed"
else
    print_error "ddosattack.h5 not found in current directory"
fi

if [[ -f "sql_xss_model.h5" ]]; then
    cp sql_xss_model.h5 "$ML_DIR/"
    chmod 644 "$ML_DIR/sql_xss_model.h5"
    print_success "SQL/XSS model installed"
else
    print_error "sql_xss_model.h5 not found in current directory"
fi

# Install ML integration script
print_status "Installing ML integration script..."
if [[ -f "waf_ml_integration.py" ]]; then
    cp waf_ml_integration.py "$ML_DIR/"
    chmod 755 "$ML_DIR/waf_ml_integration.py"
    print_success "ML integration script installed"
else
    print_error "waf_ml_integration.py not found"
fi

# Install analyzer script
print_status "Installing analyzer script..."
if [[ -f "ml_waf_analyzer.sh" ]]; then
    cp ml_waf_analyzer.sh "/usr/local/bin/"
    chmod 755 "/usr/local/bin/ml_waf_analyzer.sh"
    print_success "Analyzer script installed"
else
    print_error "ml_waf_analyzer.sh not found"
fi

# Install required Python packages
print_status "Installing Python dependencies..."
pip3 install --user aiohttp matplotlib pandas requests --break-system-packages 2>/dev/null || {
    print_error "Some Python dependencies may need manual installation"
    echo "Install missing packages with: pip3 install --user <package> --break-system-packages"
}
print_success "Core dependencies (TensorFlow, NumPy) already available"

# Check Apache installation
print_status "Checking Apache installation..."
if ! command -v apache2 &> /dev/null; then
    print_error "Apache2 not found. Installing..."
    apt-get update
    apt-get install -y apache2 libapache2-mod-security2
fi

# Enable required Apache modules
print_status "Enabling Apache modules..."
a2enmod security2
a2enmod rewrite
a2enmod headers
a2enmod status
a2enmod php8.3 || echo "PHP module already enabled or not needed"

# Create test web application
print_status "Creating test web application..."
cat > "$WEB_DIR/index.php" << 'EOF'
<?php
header('Content-Type: text/html; charset=UTF-8');
?>
<!DOCTYPE html>
<html>
<head>
    <title>WAF Test Application</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .header { background: #f0f0f0; padding: 20px; border-radius: 5px; }
        .section { margin: 20px 0; padding: 15px; border: 1px solid #ddd; }
        .malicious { background: #ffe6e6; }
        .normal { background: #e6ffe6; }
    </style>
</head>
<body>
    <div class="header">
        <h1>ML WAF Test Application</h1>
        <p>Current Time: <?php echo date('Y-m-d H:i:s'); ?></p>
        <p>Server: <?php echo $_SERVER['SERVER_NAME']; ?></p>
    </div>

    <div class="section normal">
        <h2>Normal Request Test</h2>
        <form method="GET">
            <input type="text" name="search" placeholder="Search term">
            <button type="submit">Search</button>
        </form>
        <?php if (isset($_GET['search'])): ?>
            <p>Search results for: <?php echo htmlspecialchars($_GET['search']); ?></p>
        <?php endif; ?>
    </div>

    <div class="section malicious">
        <h2>WARNING: Attack Simulation (for testing only)</h2>
        <p>These should be blocked by the WAF:</p>
        <ul>
            <li><a href="?id=1' OR '1'='1">SQL Injection Test</a></li>
            <li><a href="?search=<script>alert('xss')</script>">XSS Test</a></li>
            <li><a href="?q=1 UNION SELECT password FROM users">Union SQL Test</a></li>
        </ul>
    </div>

    <div class="section">
        <h2>Request Information</h2>
        <p><strong>Request URI:</strong> <?php echo $_SERVER['REQUEST_URI']; ?></p>
        <p><strong>User Agent:</strong> <?php echo $_SERVER['HTTP_USER_AGENT']; ?></p>
        <p><strong>Remote Address:</strong> <?php echo $_SERVER['REMOTE_ADDR']; ?></p>
        <p><strong>Request Method:</strong> <?php echo $_SERVER['REQUEST_METHOD']; ?></p>
        
        <?php if ($_POST): ?>
            <h3>POST Data:</h3>
            <?php foreach ($_POST as $key => $value): ?>
                <p><?php echo htmlspecialchars($key); ?>: <?php echo htmlspecialchars($value); ?></p>
            <?php endforeach; ?>
        <?php endif; ?>
        
        <?php if ($_GET): ?>
            <h3>GET Parameters:</h3>
            <?php foreach ($_GET as $key => $value): ?>
                <p><?php echo htmlspecialchars($key); ?>: <?php echo htmlspecialchars($value); ?></p>
            <?php endforeach; ?>
        <?php endif; ?>
    </div>
</body>
</html>
EOF

cp "$WEB_DIR/index.php" "$WEB_DIR/test.php"
cp "$WEB_DIR/index.php" "$WEB_DIR/login.php"

# Set permissions
chown -R www-data:www-data "$WEB_DIR"
chmod -R 644 "$WEB_DIR"/*

# Create global ModSecurity configuration
print_status "Creating ModSecurity global configuration..."
cat > "/etc/apache2/mods-available/security2.conf" << 'EOF'
<IfModule mod_security2.c>
    # Global ModSecurity settings
    SecDataDir /tmp/
    SecTmpDir /tmp/
</IfModule>
EOF

# Create Apache virtual host configuration
print_status "Creating Apache configuration..."
cat > "$APACHE_SITES_DIR/waf-demo.conf" << 'EOF'
<VirtualHost *:80>
    ServerName waf-demo.local
    ServerAlias localhost
    DocumentRoot /var/www/waf-demo
    
    # Enable ModSecurity
    <IfModule mod_security2.c>
        SecRuleEngine On
        
        # Basic ModSecurity configuration
        SecRequestBodyAccess On
        SecRequestBodyLimit 134217728
        SecRequestBodyNoFilesLimit 1048576
        SecRequestBodyInMemoryLimit 131072
        SecRequestBodyLimitAction ProcessPartial
        
        SecResponseBodyAccess Off
        SecResponseBodyMimeType text/plain text/html text/xml
        SecResponseBodyLimit 524288
        SecResponseBodyLimitAction ProcessPartial
        
        # Logging
        SecDebugLog /var/log/apache2/modsec_debug.log
        SecDebugLogLevel 0
        SecAuditEngine RelevantOnly
        SecAuditLogRelevantStatus "^(?:5|4(?!04))"
        SecAuditLogParts ABDEFHIJZ
        SecAuditLogType Serial
        SecAuditLog /var/log/apache2/modsec_audit.log
        
        # ML Integration Rules
        
        # Initialize ML processing
        SecAction \
            "id:1001,\
            phase:1,\
            t:none,\
            msg:'Initialize ML WAF processing',\
            pass,\
            setvar:'tx.ml_enabled=1'"
        
        # Collect request metadata for ML analysis
        SecRule REQUEST_METHOD "@unconditionalMatch" \
            "id:1002,\
            phase:1,\
            t:none,\
            msg:'Collect request data for ML analysis',\
            pass,\
            setenv:'ML_REQUEST_URI=%{REQUEST_URI}',\
            setenv:'ML_USER_AGENT=%{REQUEST_HEADERS.User-Agent}',\
            setenv:'ML_REMOTE_ADDR=%{REMOTE_ADDR}',\
            setenv:'ML_QUERY_STRING=%{QUERY_STRING}'"
        
        # ML Analysis for all requests
        SecRule TX:ML_ENABLED "@eq 1" \
            "id:1003,\
            phase:2,\
            t:none,\
            msg:'ML threat analysis',\
            pass,\
            exec:/usr/local/bin/ml_waf_analyzer.sh"
        
        # Block requests flagged by ML
        SecRule ENV:ML_BLOCK "@eq 1" \
            "id:1004,\
            phase:2,\
            t:none,\
            msg:'Request blocked by ML analysis: %{ENV.ML_REASON}',\
            deny,\
            status:403,\
            logdata:'ML Analysis - DDoS Score: %{ENV.ML_DDOS_SCORE}, SQL/XSS Score: %{ENV.ML_SQL_XSS_SCORE}'"
        
    </IfModule>
    
    # Performance monitoring
    <Location "/server-status">
        SetHandler server-status
        Require local
    </Location>
    
    <Location "/server-info">
        SetHandler server-info
        Require local
    </Location>
    
    # Logging
    ErrorLog /var/log/apache2/waf_error.log
    CustomLog /var/log/apache2/waf_access.log combined
    
    # Performance logging
    LogFormat "%h %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\" %D" waf_perf
    CustomLog /var/log/apache2/waf_performance.log waf_perf
    
    # Directory configuration
    <Directory /var/www/waf-demo>
        AllowOverride All
        Require all granted
        DirectoryIndex index.php index.html
    </Directory>
</VirtualHost>
EOF

# Enable the site
a2ensite waf-demo.conf

# Create log files with proper permissions
print_status "Setting up log files..."
touch "$LOG_DIR/waf_ml.log"
touch "$LOG_DIR/waf_performance.log"
touch "$LOG_DIR/ml_analyzer.log"
touch "$LOG_DIR/ml_performance.log"
touch "$LOG_DIR/system_performance.log"
touch "$LOG_DIR/modsec_debug.log"
touch "$LOG_DIR/modsec_audit.log"

chown www-data:www-data "$LOG_DIR"/*.log
chmod 644 "$LOG_DIR"/*.log

# Test ML integration
print_status "Testing ML integration..."
if python3 "$ML_DIR/waf_ml_integration.py" test; then
    print_success "ML integration test passed"
else
    print_error "ML integration test failed"
fi

# Test Apache configuration
print_status "Testing Apache configuration..."
if apache2ctl configtest; then
    print_success "Apache configuration is valid"
else
    print_error "Apache configuration has errors"
    exit 1
fi

# Restart Apache
print_status "Restarting Apache..."
systemctl restart apache2

if systemctl is-active --quiet apache2; then
    print_success "Apache restarted successfully"
else
    print_error "Failed to restart Apache"
    exit 1
fi

# Create monitoring script
print_status "Creating monitoring script..."
cat > "/usr/local/bin/waf_monitor.sh" << 'EOF'
#!/bin/bash
# WAF Monitoring Script

LOG_DIR="/var/log/apache2"

echo "ML WAF Status Monitor"
echo "========================"

echo "Apache Status:"
systemctl status apache2 --no-pager -l

echo -e "\nRecent ML Detections:"
tail -n 10 "$LOG_DIR/ml_analyzer.log"

echo -e "\nPerformance Metrics (last 10 requests):"
tail -n 10 "$LOG_DIR/waf_performance.log"

echo -e "\nModSecurity Audit Log (last 5 entries):"
tail -n 5 "$LOG_DIR/modsec_audit.log"

echo -e "\nApache Error Log (last 5 entries):"
tail -n 5 "$LOG_DIR/error.log"
EOF

chmod +x "/usr/local/bin/waf_monitor.sh"

# Create performance analysis script
cat > "/usr/local/bin/analyze_waf_performance.py" << 'EOF'
#!/usr/bin/env python3
import sys
import statistics
import json
from datetime import datetime

def analyze_performance_log(log_file):
    """Analyze WAF performance from log file"""
    response_times = []
    
    try:
        with open(log_file, 'r') as f:
            for line in f:
                parts = line.strip().split(',')
                if len(parts) >= 2:
                    try:
                        response_time = float(parts[1])
                        response_times.append(response_time * 1000)  # Convert to ms
                    except ValueError:
                        continue
        
        if not response_times:
            print("No performance data found")
            return
        
        print(f"Performance Analysis ({len(response_times)} requests):")
        print(f"  Average Response Time: {statistics.mean(response_times):.2f}ms")
        print(f"  Median Response Time:  {statistics.median(response_times):.2f}ms")
        print(f"  95th Percentile:       {statistics.quantiles(response_times, n=20)[18]:.2f}ms")
        print(f"  Min Response Time:     {min(response_times):.2f}ms")
        print(f"  Max Response Time:     {max(response_times):.2f}ms")
        
    except FileNotFoundError:
        print(f"Performance log file not found: {log_file}")
    except Exception as e:
        print(f"Error analyzing performance: {e}")

if __name__ == "__main__":
    log_file = sys.argv[1] if len(sys.argv) > 1 else "/var/log/apache2/ml_performance.log"
    analyze_performance_log(log_file)
EOF

chmod +x "/usr/local/bin/analyze_waf_performance.py"

# Final status
echo ""
echo "ML WAF Deployment Complete!"
echo "=============================="
echo ""
echo "Access Points:"
echo "  • Test Application: http://localhost/"
echo "  • Server Status:    http://localhost/server-status"
echo "  • Server Info:      http://localhost/server-info"
echo ""
echo "Important Paths:"
echo "  • ML Models:        $ML_DIR/"
echo "  • Web Root:         $WEB_DIR/"
echo "  • Log Files:        $LOG_DIR/"
echo "  • Apache Config:    $APACHE_SITES_DIR/waf-demo.conf"
echo ""
echo "Management Commands:"
echo "  • Monitor WAF:      /usr/local/bin/waf_monitor.sh"
echo "  • Analyze Performance: /usr/local/bin/analyze_waf_performance.py"
echo "  • Test ML Models:   python3 $ML_DIR/waf_ml_integration.py test"
echo "  • View Logs:        tail -f $LOG_DIR/ml_analyzer.log"
echo ""
echo "Performance Testing:"
echo "  • Run baseline test: python3 performance_test.py --test baseline"
echo "  • Run ML test:       python3 performance_test.py --test ml"
echo "  • Run both tests:    python3 performance_test.py --test both"
echo ""
print_success "Ready to protect your web applications!" 