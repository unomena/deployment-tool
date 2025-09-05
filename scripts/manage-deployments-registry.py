#!/usr/bin/env python3
"""
manage-deployments-registry.py - Deployment Registry Management Script

This script manages the deployments.yml registry file that tracks all active deployments.
It provides functions to add, update, remove, and query deployment information.

Usage:
    python manage-deployments-registry.py add --project PROJECT --environment ENV --data DATA_JSON
    python manage-deployments-registry.py remove --project PROJECT --environment ENV
    python manage-deployments-registry.py update --project PROJECT --environment ENV --data DATA_JSON
    python manage-deployments-registry.py get --project PROJECT --environment ENV
    python manage-deployments-registry.py list
"""

import argparse
import json
import os
import sys
import yaml
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Any, Optional

# Default deployments registry file path
DEFAULT_REGISTRY_PATH = "/home/ubuntu/Workspace/deployment-tool/deployments.yml"

class DeploymentRegistry:
    def __init__(self, registry_path: str = DEFAULT_REGISTRY_PATH):
        self.registry_path = Path(registry_path)
        self.data = self._load_registry()
    
    def _load_registry(self) -> Dict[str, Any]:
        """Load the deployments registry from YAML file."""
        if not self.registry_path.exists():
            return {
                "deployments": {},
                "last_updated": datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'),
                "version": "1.0"
            }
        
        try:
            with open(self.registry_path, 'r') as f:
                return yaml.safe_load(f) or {}
        except Exception as e:
            print(f"Error loading registry: {e}", file=sys.stderr)
            return {
                "deployments": {},
                "last_updated": datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'),
                "version": "1.0"
            }
    
    def _save_registry(self):
        """Save the deployments registry to YAML file."""
        self.data["last_updated"] = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
        
        # Ensure parent directory exists
        self.registry_path.parent.mkdir(parents=True, exist_ok=True)
        
        try:
            with open(self.registry_path, 'w') as f:
                yaml.dump(self.data, f, default_flow_style=False, indent=2, sort_keys=False)
        except Exception as e:
            print(f"Error saving registry: {e}", file=sys.stderr)
            raise
    
    def add_deployment(self, project: str, environment: str, deployment_data: Dict[str, Any]):
        """Add or update a deployment in the registry."""
        if "deployments" not in self.data:
            self.data["deployments"] = {}
        
        if project not in self.data["deployments"]:
            self.data["deployments"][project] = {"environments": {}}
        
        if "environments" not in self.data["deployments"][project]:
            self.data["deployments"][project]["environments"] = {}
        
        # Add deployment timestamp if not provided
        if "deployed_at" not in deployment_data:
            deployment_data["deployed_at"] = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
        
        self.data["deployments"][project]["environments"][environment] = deployment_data
        self._save_registry()
    
    def remove_deployment(self, project: str, environment: str) -> bool:
        """Remove a deployment from the registry."""
        if ("deployments" not in self.data or 
            project not in self.data["deployments"] or
            "environments" not in self.data["deployments"][project] or
            environment not in self.data["deployments"][project]["environments"]):
            return False
        
        del self.data["deployments"][project]["environments"][environment]
        
        # Remove project if no environments left
        if not self.data["deployments"][project]["environments"]:
            del self.data["deployments"][project]
        
        self._save_registry()
        return True
    
    def get_deployment(self, project: str, environment: str) -> Optional[Dict[str, Any]]:
        """Get deployment information for a specific project and environment."""
        if ("deployments" not in self.data or 
            project not in self.data["deployments"] or
            "environments" not in self.data["deployments"][project] or
            environment not in self.data["deployments"][project]["environments"]):
            return None
        
        return self.data["deployments"][project]["environments"][environment]
    
    def list_deployments(self) -> Dict[str, Any]:
        """Get all deployments."""
        return self.data.get("deployments", {})
    
    def update_service_status(self, project: str, environment: str, service_name: str, 
                            status: str, pid: Optional[int] = None):
        """Update the status of a specific service."""
        deployment = self.get_deployment(project, environment)
        if not deployment or "services" not in deployment:
            return False
        
        for service in deployment["services"]:
            if service["name"] == service_name:
                service["status"] = status
                if pid is not None:
                    service["pid"] = pid
                elif "pid" in service and status in ["STOPPED", "FATAL"]:
                    service.pop("pid", None)
                break
        
        self.add_deployment(project, environment, deployment)
        return True


def create_deployment_data_from_config(config_data: Dict[str, Any], 
                                     git_url: str, 
                                     branch: str,
                                     deployment_path: str,
                                     python_version: str = None,
                                     django_version: str = None) -> Dict[str, Any]:
    """Create deployment data structure from deployment configuration."""
    
    # Extract project name from deployment path
    project = deployment_path.split('/')[-3] if len(deployment_path.split('/')) >= 3 else "unknown"
    
    # Build services list from config
    services = []
    if "services" in config_data:
        for service_name, service_config in config_data["services"].items():
            service_data = {
                "name": f"{project}-{config_data.get('environment', 'unknown')}-{service_name}",
                "type": service_name,
                "status": "UNKNOWN",
                "command": service_config.get("command", "")
            }
            
            # Extract port from command if it's a web service
            if service_name == "web" and "bind" in service_config.get("command", ""):
                try:
                    bind_part = service_config["command"].split("--bind")[1].strip().split()[0]
                    if ":" in bind_part:
                        service_data["port"] = int(bind_part.split(":")[-1])
                except (IndexError, ValueError):
                    pass
            
            services.append(service_data)
    
    # Build directories structure
    directories = {
        "code": f"{deployment_path}/code",
        "venv": f"{deployment_path}/venv", 
        "logs": f"{deployment_path}/logs",
        "config": f"{deployment_path}/config"
    }
    
    return {
        "git_url": git_url,
        "branch": branch,
        "deployed_at": datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'),
        "python_version": python_version,
        "django_version": django_version,
        "deployment_path": deployment_path,
        "services": services,
        "directories": directories,
        "config_file": f"deploy-{config_data.get('environment', 'unknown')}.yml"
    }


def main():
    parser = argparse.ArgumentParser(description="Manage deployment registry")
    parser.add_argument("--registry-path", default=DEFAULT_REGISTRY_PATH,
                       help="Path to deployments registry file")
    
    subparsers = parser.add_subparsers(dest="command", help="Available commands")
    
    # Add deployment
    add_parser = subparsers.add_parser("add", help="Add deployment")
    add_parser.add_argument("--project", required=True, help="Project name")
    add_parser.add_argument("--environment", required=True, help="Environment name")
    add_parser.add_argument("--data", required=True, help="Deployment data as JSON")
    
    # Remove deployment
    remove_parser = subparsers.add_parser("remove", help="Remove deployment")
    remove_parser.add_argument("--project", required=True, help="Project name")
    remove_parser.add_argument("--environment", required=True, help="Environment name")
    
    # Update deployment
    update_parser = subparsers.add_parser("update", help="Update deployment")
    update_parser.add_argument("--project", required=True, help="Project name")
    update_parser.add_argument("--environment", required=True, help="Environment name")
    update_parser.add_argument("--data", required=True, help="Deployment data as JSON")
    
    # Get deployment
    get_parser = subparsers.add_parser("get", help="Get deployment")
    get_parser.add_argument("--project", required=True, help="Project name")
    get_parser.add_argument("--environment", required=True, help="Environment name")
    
    # List deployments
    list_parser = subparsers.add_parser("list", help="List all deployments")
    
    # Update service status
    status_parser = subparsers.add_parser("update-service", help="Update service status")
    status_parser.add_argument("--project", required=True, help="Project name")
    status_parser.add_argument("--environment", required=True, help="Environment name")
    status_parser.add_argument("--service", required=True, help="Service name")
    status_parser.add_argument("--status", required=True, help="Service status")
    status_parser.add_argument("--pid", type=int, help="Process ID")
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return 1
    
    registry = DeploymentRegistry(args.registry_path)
    
    try:
        if args.command == "add":
            data = json.loads(args.data)
            registry.add_deployment(args.project, args.environment, data)
            print(f"Added deployment: {args.project}/{args.environment}")
        
        elif args.command == "remove":
            if registry.remove_deployment(args.project, args.environment):
                print(f"Removed deployment: {args.project}/{args.environment}")
            else:
                print(f"Deployment not found: {args.project}/{args.environment}")
                return 1
        
        elif args.command == "update":
            data = json.loads(args.data)
            registry.add_deployment(args.project, args.environment, data)
            print(f"Updated deployment: {args.project}/{args.environment}")
        
        elif args.command == "get":
            deployment = registry.get_deployment(args.project, args.environment)
            if deployment:
                print(json.dumps(deployment, indent=2))
            else:
                print(f"Deployment not found: {args.project}/{args.environment}")
                return 1
        
        elif args.command == "list":
            deployments = registry.list_deployments()
            print(json.dumps(deployments, indent=2))
        
        elif args.command == "update-service":
            if registry.update_service_status(args.project, args.environment, 
                                            args.service, args.status, args.pid):
                print(f"Updated service status: {args.project}/{args.environment}/{args.service} -> {args.status}")
            else:
                print(f"Service not found: {args.project}/{args.environment}/{args.service}")
                return 1
    
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
