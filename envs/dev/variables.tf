variable "region" {
  type    = string
  default = "ap-south-1"
}
variable "environment" {
  type    = string
  default = "dev"
}
variable "github_owner" {
  type    = string
  default = "Om25091210"
}
variable "alert_email" {
  description = "Receives alarms and budget alerts (must confirm the SNS subscription email)"
  type        = string
}
variable "monthly_budget_usd" {
  description = "Dev estimate is about USD 38; alert early at 60/80/100% of this cap"
  type        = number
  default     = 60
}
variable "instance_type" {
  type    = string
  default = "t4g.small"
}
variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}
variable "enable_schedule" {
  description = "Stop EC2 and RDS outside working hours (IST) to save cost"
  type        = bool
  default     = true
}
variable "cors_allowed_origins" {
  type    = list(string)
  default = []
}
