variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "instance_type" {
  description = "EC2 instance type for control-plane and worker nodes"
  type        = string
  default     = "t3.small"
}

variable "key_pair_name" {
  description = "Name of the existing AWS key pair for SSH access"
  type        = string
}

variable "my_ip" {
  description = "Your public IP in CIDR notation, for SSH access (e.g. 1.2.3.4/32)"
  type        = string
}

variable "worker_count" {
  description = "Number of k3s worker nodes"
  type        = number
  default     = 2
}

variable "project_name" {
  description = "Project name used for tagging resources"
  type        = string
  default     = "capstone-phoenix"
}
