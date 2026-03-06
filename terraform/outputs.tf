# ============================================================================
# Weather Agent Runtime Outputs
# ============================================================================

output "agent_runtime_id" {
  description = "ID of the weather agent runtime"
  value       = module.agentcore_runtime.id
}

output "agent_runtime_arn" {
  description = "ARN of the weather agent runtime"
  value       = module.agentcore_runtime.arn
}

output "agent_ecr_repository_url" {
  description = "URL of the ECR repository for weather agent"
  value       = module.container_registry.repository_url
}

output "agent_execution_role_arn" {
  description = "ARN of the weather agent execution role"
  value       = module.agent_execution_role.arn
}


# ============================================================================
# Build & Storage Outputs
# ============================================================================
output "source_bucket_name" {
  description = "S3 bucket containing weather agent source code"
  value       = module.agent_source_bucket.id
}

output "results_bucket_name" {
  description = "Name of the S3 bucket for agent results"
  value       = module.agent_results_bucket.id
}

# ============================================================================
# Testing Information
# ============================================================================

output "test_agent_command" {
  description = "AWS CLI command to test weather agent"
  value       = "aws bedrock-agentcore invoke-agent-runtime --agent-runtime-arn ${module.agentcore_runtime.arn} --qualifier DEFAULT --payload '{\"prompt\": \"What's the weather like today and suggest activities?\"}' --region ${data.aws_region.current.id} response.json"
}

output "test_script_command" {
  description = "Command to run the comprehensive test script"
  value       = "python test_weather_agent.py ${module.agentcore_runtime.arn}"
}

# ============================================================================
# Tool Resource Outputs
# ============================================================================

output "browser_id" {
  description = "ID of the browser tool"
  value       = module.agentcore_browser.browser_id
}

output "browser_arn" {
  description = "ARN of the browser tool"
  value       = module.agentcore_browser.arn
}

output "code_interpreter_id" {
  description = "ID of the code interpreter tool"
  value       = module.agentcore_code_interpreter.code_interpreter_id
}

output "code_interpreter_arn" {
  description = "ARN of the code interpreter tool"
  value       = module.agentcore_code_interpreter.arn
}

output "memory_id" {
  description = "ID of the memory resource"
  value       = module.agentcore_memory.id
}

output "memory_arn" {
  description = "ARN of the memory resource"
  value       = module.agentcore_memory.arn
}