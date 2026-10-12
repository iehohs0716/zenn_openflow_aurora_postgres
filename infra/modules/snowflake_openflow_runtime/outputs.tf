output "deployment_name" {
  description = "Deployment 名"
  value       = local.deployment_name
}

output "runtime_name" {
  description = "Runtime 名"
  value       = snowflake_openflow_runtime.this.name
}
