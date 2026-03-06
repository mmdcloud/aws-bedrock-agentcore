resource "aws_bedrockagentcore_agent_runtime" "weather_agent" {
  agent_runtime_name = "${replace(var.stack_name, "-", "_")}_${var.agent_name}"
  description        = "Weather agent runtime for ${var.stack_name}"
  role_arn           = var.role_arn

  agent_runtime_artifact {
    container_configuration {
      container_uri = var.container_uri
    }
  }

  network_configuration {
    network_mode = var.network_mode
  }

  environment_variables = var.environment_variables

  tags = {
    Name        = "${var.stack_name}-agent-runtime"
    Environment = "production"
    Module      = "BedrockAgentCore"
    Agent       = "WeatherAgent"  
  }  
}