#!/usr/bin/env python3
"""
deployment-status-registry.py - Enhanced Deployment Status Report using Registry

This script generates a comprehensive deployment status report by reading from
the deployments.yml registry file and combining it with live system status.
"""

import os
import sys
import yaml
import subprocess
import json
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Any, Optional

# Color codes for terminal output
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    PURPLE = '\033[0;35m'
    CYAN = '\033[0;36m'
    WHITE = '\033[1;37m'
    NC = '\033[0m'  # No Color
    
    @staticmethod
    def colorize_status(status: str) -> str:
        """Apply color coding to status based on state"""
        status_upper = status.upper()
        if status_upper == 'RUNNING':
            return f"{Colors.GREEN}{status}{Colors.NC}"
        elif status_upper in ['FAILED', 'FATAL', 'ERROR', 'STOPPED']:
            return f"{Colors.RED}{status}{Colors.NC}"
        elif status_upper in ['STARTING', 'STOPPING', 'RESTARTING', 'UNKNOWN']:
            return f"{Colors.YELLOW}{status}{Colors.NC}"
        else:
            return status

# Default registry path
DEFAULT_REGISTRY_PATH = "/home/ubuntu/Workspace/deployment-tool/deployments.yml"

class DeploymentStatusReporter:
    def __init__(self, registry_path: str = DEFAULT_REGISTRY_PATH):
        self.registry_path = Path(registry_path)
        self.deployments = self._load_deployments()
    
    def _load_deployments(self) -> Dict[str, Any]:
        """Load deployments from registry file"""
        if not self.registry_path.exists():
            return {}
        
        try:
            with open(self.registry_path, 'r') as f:
                data = yaml.safe_load(f) or {}
                return data.get('deployments', {})
        except Exception as e:
            print(f"Warning: Could not load deployments registry: {e}", file=sys.stderr)
            return {}
    
    def _get_supervisor_status(self) -> Dict[str, Dict[str, Any]]:
        """Get supervisor service status"""
        try:
            result = subprocess.run(
                ["sudo", "supervisorctl", "status"],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            services = {}
            if result.returncode == 0:
                for line in result.stdout.strip().split('\n'):
                    if line.strip():
                        parts = line.split()
                        if len(parts) >= 2:
                            service_name = parts[0]
                            status = parts[1]
                            pid = None
                            
                            # Extract PID if running
                            if status == "RUNNING" and len(parts) >= 4:
                                # Look for "pid XXXXX," pattern
                                for i, part in enumerate(parts[2:], 2):
                                    if part == "pid" and i + 1 < len(parts):
                                        pid = parts[i + 1].rstrip(',')
                                        break
                            
                            services[service_name] = {
                                "status": status,
                                "pid": pid,
                                "raw_line": line
                            }
            
            return services
        except Exception as e:
            print(f"Warning: Could not get supervisor status: {e}", file=sys.stderr)
            return {}
    
    def _get_system_info(self) -> Dict[str, str]:
        """Get system information"""
        info = {}
        
        try:
            # CPU usage
            result = subprocess.run(
                ["top", "-bn1"], capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                for line in result.stdout.split('\n'):
                    if '%Cpu(s):' in line:
                        cpu_part = line.split('%Cpu(s):')[1].split(',')[0].strip()
                        info['cpu'] = cpu_part.replace(' us', '')
                        break
        except:
            info['cpu'] = 'N/A'
        
        try:
            # Memory usage
            result = subprocess.run(
                ["free", "-h"], capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                lines = result.stdout.strip().split('\n')
                if len(lines) >= 2:
                    mem_line = lines[1].split()
                    if len(mem_line) >= 3:
                        total = mem_line[1]
                        used = mem_line[2]
                        info['memory'] = f"{used}/{total}"
        except:
            info['memory'] = 'N/A'
        
        try:
            # Disk usage
            result = subprocess.run(
                ["df", "-h", "/"], capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                lines = result.stdout.strip().split('\n')
                if len(lines) >= 2:
                    disk_line = lines[1].split()
                    if len(disk_line) >= 5:
                        info['disk'] = disk_line[4]  # Use% column
        except:
            info['disk'] = 'N/A'
        
        try:
            # Load average
            result = subprocess.run(
                ["uptime"], capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                uptime_output = result.stdout.strip()
                if 'load average:' in uptime_output:
                    load_part = uptime_output.split('load average:')[1].strip()
                    info['load'] = load_part
        except:
            info['load'] = 'N/A'
        
        return info
    
    def _check_service_health(self) -> Dict[str, bool]:
        """Check health of system services"""
        services = {
            'supervisor': False,
            'nginx': False,
            'postgresql': False
        }
        
        for service in services.keys():
            try:
                result = subprocess.run(
                    ["systemctl", "is-active", service],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                services[service] = result.returncode == 0 and result.stdout.strip() == 'active'
            except:
                pass
        
        return services
    
    def generate_report(self) -> str:
        """Generate comprehensive deployment status report"""
        report_lines = []
        
        # Header
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S %Z")
        report_lines.extend([
            "",
            "=" * 80,
            f"DEPLOYMENT STATUS REPORT - {timestamp}",
            "=" * 80,
            ""
        ])
        
        # System Overview
        system_info = self._get_system_info()
        report_lines.extend([
            "SYSTEM OVERVIEW",
            "=",
            f"CPU: {system_info.get('cpu', 'N/A')} | "
            f"Memory: {system_info.get('memory', 'N/A')} | "
            f"Disk: {system_info.get('disk', 'N/A')} | "
            f"Load: {system_info.get('load', 'N/A')}",
            ""
        ])
        
        # Deployments Overview
        supervisor_status = self._get_supervisor_status()
        
        if self.deployments:
            report_lines.extend([
                "DEPLOYMENTS OVERVIEW",
                "=",
                f"{'PROJECT':<15} {'ENVIRONMENT':<12} {'BRANCH':<10} {'PYTHON':<12} {'DJANGO':<12} {'LAST MODIFIED':<19}",
                f"{'-------':<15} {'-----------':<12} {'------':<10} {'------':<12} {'------':<12} {'-------------':<19}"
            ])
            
            for project, project_data in self.deployments.items():
                environments = project_data.get('environments', {})
                for env, env_data in environments.items():
                    python_ver = env_data.get('python_version', 'unknown')
                    django_ver = env_data.get('django_version', 'unknown')
                    deployed_at = env_data.get('deployed_at', 'unknown')
                    
                    # Format timestamp
                    try:
                        if deployed_at != 'unknown':
                            dt = datetime.fromisoformat(deployed_at.replace('Z', '+00:00'))
                            deployed_at = dt.strftime('%Y-%m-%d %H:%M:%S')
                    except:
                        pass
                    
                    branch = env_data.get('branch', 'unknown')
                    
                    report_lines.append(
                        f"{project:<15} {env:<12} {branch:<10} {python_ver:<12} {django_ver:<12} {deployed_at:<19}"
                    )
        else:
            report_lines.extend([
                "DEPLOYMENTS OVERVIEW",
                "=",
                "No deployments found in registry"
            ])
        
        report_lines.append("")
        
        # Services Status
        report_lines.extend([
            "SUPERVISOR SERVICES STATUS",
            "=",
            f"{'SERVICE':<20} {'PROJECT':<15} {'STATUS':<10} {'PID':<10}",
            f"{'-------':<20} {'-------':<15} {'------':<10} {'---':<10}"
        ])
        
        if self.deployments:
            for project, project_data in self.deployments.items():
                environments = project_data.get('environments', {})
                for env, env_data in environments.items():
                    services = env_data.get('services', [])
                    for service in services:
                        service_name = service.get('name', 'unknown')
                        service_status = 'UNKNOWN'
                        service_pid = 'N/A'
                        
                        # Get live status from supervisor
                        # Try exact match first, then try with group prefix
                        sup_info = None
                        if service_name in supervisor_status:
                            sup_info = supervisor_status[service_name]
                        else:
                            # Try with group prefix (e.g., sampleapp-dev:sampleapp-dev-web)
                            group_name = f"{project}-{env}"
                            full_service_name = f"{group_name}:{service_name}"
                            if full_service_name in supervisor_status:
                                sup_info = supervisor_status[full_service_name]
                            else:
                                # For worker services, check for numbered variants (_00, _01, etc.)
                                for sup_name in supervisor_status.keys():
                                    if sup_name.startswith(f"{group_name}:{service_name}_"):
                                        sup_info = supervisor_status[sup_name]
                                        break
                        
                        if sup_info:
                            service_status = sup_info['status']
                            service_pid = sup_info['pid'] or 'N/A'
                        
                        # Apply color coding to status with proper spacing
                        colored_status = Colors.colorize_status(service_status)
                        
                        # Calculate padding needed after the colored status
                        status_length = len(service_status)
                        padding_needed = max(0, 10 - status_length)
                        padding = " " * padding_needed
                        
                        report_lines.append(
                            f"{service_name:<20} {project:<15} {colored_status}{padding} {service_pid:<10}"
                        )
        
        if not any('RUNNING' in line for line in report_lines[-10:]):
            report_lines.append("No active services found")
        
        report_lines.append("")
        
        # Exposed Ports and Services
        report_lines.extend([
            "EXPOSED PORTS AND SERVICES",
            "=",
            f"{'PORT':<8} {'SERVICE/PROCESS':<20} {'TYPE':<15} {'PROJECT':<15}",
            f"{'----':<8} {'---------------':<20} {'----':<15} {'-------':<15}"
        ])
        
        ports_found = False
        if self.deployments:
            for project, project_data in self.deployments.items():
                environments = project_data.get('environments', {})
                for env, env_data in environments.items():
                    services = env_data.get('services', [])
                    for service in services:
                        service_name = service.get('name', 'unknown')
                        service_type = service.get('type', 'unknown')
                        
                        # Show port if available
                        if 'port' in service:
                            port = service['port']
                            report_lines.append(
                                f"{port:<8} {service_name:<20} {'supervisor':<15} {project:<15}"
                            )
                            ports_found = True
                        
                        # Show Redis port for celery services (common pattern)
                        if service_type in ['celery-worker', 'celery-beat']:
                            report_lines.append(
                                f"{'6379':<8} {service_name:<20} {'supervisor':<15} {project:<15}"
                            )
                            ports_found = True
        
        if not ports_found:
            report_lines.append("No exposed ports found")
        
        report_lines.append("")
        
        # Quick Health Check
        health_status = self._check_service_health()
        report_lines.extend([
            "QUICK HEALTH CHECK",
            "="
        ])
        
        for service, is_healthy in health_status.items():
            status_symbol = "✓" if is_healthy else "✗"
            service_name = service.replace('_', ' ').title()
            report_lines.append(f"{status_symbol} {service_name} is {'running' if is_healthy else 'not running'}")
        
        report_lines.extend([
            "",
            "",
            "=" * 80,
            "END OF REPORT",
            "=" * 80
        ])
        
        return '\n'.join(report_lines)


def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Generate deployment status report from registry")
    parser.add_argument("--registry-path", default=DEFAULT_REGISTRY_PATH,
                       help="Path to deployments registry file")
    parser.add_argument("--format", choices=['text', 'json'], default='text',
                       help="Output format")
    
    args = parser.parse_args()
    
    try:
        reporter = DeploymentStatusReporter(args.registry_path)
        
        if args.format == 'json':
            # Output raw data as JSON
            output = {
                'deployments': reporter.deployments,
                'system_info': reporter._get_system_info(),
                'supervisor_status': reporter._get_supervisor_status(),
                'health_status': reporter._check_service_health(),
                'timestamp': datetime.now().isoformat()
            }
            print(json.dumps(output, indent=2))
        else:
            # Output formatted text report
            report = reporter.generate_report()
            print(report)
        
        return 0
        
    except Exception as e:
        print(f"Error generating status report: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
