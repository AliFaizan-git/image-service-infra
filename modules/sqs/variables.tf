variable "name" {
  description = "Queue base name"
  type        = string
}

variable "fifo" {
  type    = bool
  default = false
}

variable "visibility_timeout_seconds" {
  type    = number
  default = 60
}

variable "message_retention_seconds" {
  type    = number
  default = 345600 # 4 days
}

variable "receive_wait_time_seconds" {
  description = "Long polling"
  type        = number
  default     = 20
}

variable "delay_seconds" {
  type    = number
  default = 0
}

variable "max_message_size" {
  type    = number
  default = 262144 # 256KB
}

variable "max_receive_count" {
  type    = number
  default = 5
}

variable "dlq_message_retention_seconds" {
  type    = number
  default = 1209600 # 14 days
}

variable "allowed_s3_bucket_arns" {
  type    = list(string)
  default = []
}