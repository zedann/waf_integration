#!/usr/bin/env python3
"""
ML-based Web Application Firewall Integration
Combines DDoS detection and SQL/XSS detection models
"""

import sys
import json
import time
import logging
import numpy as np
from tensorflow.keras.models import load_model
import os
from urllib.parse import unquote
import re

# Configuration
CONFIG = {
    'ddos_model_path': './ddosattack.h5',  # Local path for testing
    'sql_xss_model_path': './sql_xss_model.h5',  # Local path for testing
    'ddos_threshold': 0.5,
    'sql_xss_threshold': 0.5,
    'log_file': './waf_ml.log',  # Local path for testing
    'feature_cache_size': 1000,
    'performance_log': './waf_performance.log'  # Local path for testing
}

# Setup logging
def setup_logging():
    try:
        # Try to create log files if they don't exist
        os.makedirs(os.path.dirname(CONFIG['log_file']), exist_ok=True)
        
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(CONFIG['log_file']),
                logging.StreamHandler()
            ]
        )
    except PermissionError:
        # Fall back to console-only logging
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.StreamHandler()
            ]
        )

# Initialize logging
setup_logging()

class WAFMLDetector:
    def __init__(self):
        self.ddos_model = None
        self.sql_xss_model = None
        self.load_models()
        
        # SQL/XSS normalization parameters
        self.sql_xss_mean = [535597.58, 54248.0, 552328.0, 552328.0, 939861.72,
                            401200.85, 416281.84, 425711.76, 445365.96, 448604.63,
                            519850.86, 454755.03, 1.0, 512772.62, 552328.0]
        
        self.sql_xss_scale = [277667.80, 1.0, 1.0, 1.0, 76029.01,
                             262225.14, 274441.45, 273016.26, 291008.87, 283933.66,
                             267792.49, 270823.82, 0.0, 279089.91, 1.0]
    
    def load_models(self):
        """Load both ML models"""
        try:
            start_time = time.time()
            
            if os.path.exists(CONFIG['ddos_model_path']):
                self.ddos_model = load_model(CONFIG['ddos_model_path'])
                logging.info(f"DDoS model loaded from {CONFIG['ddos_model_path']}")
            
            if os.path.exists(CONFIG['sql_xss_model_path']):
                self.sql_xss_model = load_model(CONFIG['sql_xss_model_path'])
                logging.info(f"SQL/XSS model loaded from {CONFIG['sql_xss_model_path']}")
            
            load_time = time.time() - start_time
            logging.info(f"Models loaded in {load_time:.3f} seconds")
            
        except Exception as e:
            logging.error(f"Error loading models: {str(e)}")
            sys.exit(1)
    
    def extract_ddos_features(self, request_data):
        """Extract DDoS features from request"""
        # This would typically extract network-level features
        # For demo purposes, using mock features
        features = [
            len(request_data.get('uri', '')),
            len(request_data.get('user_agent', '')),
            request_data.get('content_length', 0),
            len(request_data.get('headers', {})),
            request_data.get('connection_count', 1),
            *[0.5] * 25
        ]
        return features[:30]  # Ensure exactly 30 features
    
    def extract_sql_xss_features(self, request_data):
        """Extract SQL/XSS features from request"""
        uri = request_data.get('uri', '')
        query_string = request_data.get('query_string', '')
        post_data = request_data.get('post_data', '')
        
        # Combine all input sources
        combined_input = f"{uri} {query_string} {post_data}"
        
        # Basic feature extraction (simplified)
        features = [
            len(combined_input),
            combined_input.count("'"),
            combined_input.count('"'),
            combined_input.count('--'),
            combined_input.count('UNION'),
            combined_input.count('SELECT'),
            combined_input.count('INSERT'),
            combined_input.count('DELETE'),
            combined_input.count('<script>'),
            combined_input.count('javascript:'),
            combined_input.count('onload='),
            combined_input.count('alert('),
            1 if any(x in combined_input.lower() for x in ['sql', 'xss', 'script']) else 0,
            len(query_string),
            len(post_data)
        ]
        return features[:15]  # Ensure exactly 15 features
    
    def detect_ddos(self, request_data):
        """Detect DDoS attacks"""
        if not self.ddos_model:
            return False, 0.0
        
        try:
            features = self.extract_ddos_features(request_data)
            if len(features) != 30:
                logging.warning(f"Invalid DDoS features length: {len(features)}")
                return True, 1.0  # Block on invalid features
            
            X = np.array([features])
            prediction = self.ddos_model.predict(X, verbose=0)[0][0]
            
            is_attack = prediction > CONFIG['ddos_threshold']
            logging.info(f"DDoS prediction: {prediction:.3f}, threshold: {CONFIG['ddos_threshold']}, blocked: {is_attack}")
            
            return is_attack, float(prediction)
            
        except Exception as e:
            logging.error(f"DDoS detection error: {str(e)}")
            return True, 1.0  # Block on error
    
    def detect_sql_xss(self, request_data):
        """Detect SQL injection and XSS attacks"""
        if not self.sql_xss_model:
            return False, 0.0
        
        try:
            features = self.extract_sql_xss_features(request_data)
            if len(features) != 15:
                logging.warning(f"Invalid SQL/XSS features length: {len(features)}")
                return True, 1.0  # Block on invalid features
            
            # Standardize features
            standardized = [(float(x) - m) / s if s != 0 else 0 
                          for x, m, s in zip(features, self.sql_xss_mean, self.sql_xss_scale)]
            
            X = np.array(standardized).reshape(1, len(features), 1)  # LSTM expects 3D input
            prediction = self.sql_xss_model.predict(X, verbose=0)[0][0]
            
            is_attack = prediction > CONFIG['sql_xss_threshold']
            logging.info(f"SQL/XSS prediction: {prediction:.3f}, threshold: {CONFIG['sql_xss_threshold']}, blocked: {is_attack}")
            
            return is_attack, float(prediction)
            
        except Exception as e:
            logging.error(f"SQL/XSS detection error: {str(e)}")
            return True, 1.0  # Block on error
    
    def analyze_request(self, request_data):
        """Analyze request using both models"""
        start_time = time.time()
        
        results = {
            'timestamp': time.time(),
            'processing_time': 0,
            'blocked': False,
            'ddos_detected': False,
            'sql_xss_detected': False,
            'ddos_score': 0.0,
            'sql_xss_score': 0.0,
            'reason': 'allowed'
        }
        
        try:
            # Check DDoS
            ddos_blocked, ddos_score = self.detect_ddos(request_data)
            results['ddos_detected'] = ddos_blocked
            results['ddos_score'] = ddos_score
            
            # Check SQL/XSS
            sql_xss_blocked, sql_xss_score = self.detect_sql_xss(request_data)
            results['sql_xss_detected'] = sql_xss_blocked
            results['sql_xss_score'] = sql_xss_score
            
            # Determine final decision
            if ddos_blocked:
                results['blocked'] = True
                results['reason'] = 'ddos_attack'
            elif sql_xss_blocked:
                results['blocked'] = True
                results['reason'] = 'sql_xss_attack'
            
            results['processing_time'] = time.time() - start_time
            
            # Log performance metrics
            with open(CONFIG['performance_log'], 'a') as f:
                f.write(f"{results['timestamp']},{results['processing_time']:.6f},{results['blocked']}\n")
            
            return results
            
        except Exception as e:
            logging.error(f"Request analysis error: {str(e)}")
            results['blocked'] = True
            results['reason'] = 'analysis_error'
            results['processing_time'] = time.time() - start_time
            return results

def main():
    """Main function for command-line usage"""
    if len(sys.argv) < 2:
        print("Usage: python3 waf_ml_integration.py <mode>")
        print("Modes: analyze, test")
        sys.exit(1)
    
    mode = sys.argv[1]
    detector = WAFMLDetector()
    
    if mode == "analyze":
        # Read request data from stdin
        try:
            input_data = sys.stdin.read()
            request_data = json.loads(input_data)
            
            results = detector.analyze_request(request_data)
            
            # Output decision
            if results['blocked']:
                print("403")  # Forbidden
                sys.exit(1)
            else:
                print("200")  # OK
                sys.exit(0)
                
        except Exception as e:
            logging.error(f"Main analysis error: {str(e)}")
            print("403")
            sys.exit(1)
    
    elif mode == "test":
        # Test with sample data
        sample_requests = [
            {
                "uri": "/index.php",
                "query_string": "id=1",
                "user_agent": "Mozilla/5.0",
                "headers": {"Host": "example.com"},
                "content_length": 0,
                "connection_count": 1,
                "post_data": ""
            },
            {
                "uri": "/login.php",
                "query_string": "id=1' OR '1'='1",
                "user_agent": "Mozilla/5.0",
                "headers": {"Host": "example.com"},
                "content_length": 100,
                "connection_count": 1,
                "post_data": "<script>alert('xss')</script>"
            },
            {
                "uri": "/api/data",
                "query_string": "",
                "user_agent": "AttackBot/1.0",
                "headers": {"Host": "example.com"},
                "content_length": 0,
                "connection_count": 1000,
                "post_data": ""
            }
        ]
        
        for i, request in enumerate(sample_requests):
            print(f"\nTesting request {i+1}:")
            print(json.dumps(request, indent=2))
            
            results = detector.analyze_request(request)
            
            print(f"Results:")
            print(f"  Blocked: {results['blocked']}")
            print(f"  Reason: {results['reason']}")
            print(f"  DDoS Score: {results['ddos_score']:.3f}")
            print(f"  SQL/XSS Score: {results['sql_xss_score']:.3f}")
            print(f"  Processing Time: {results['processing_time']:.6f}s")

if __name__ == "__main__":
    main() 