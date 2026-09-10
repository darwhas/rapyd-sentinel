############################################
# Networking: two isolated VPCs
############################################

module "vpc_gateway" {
  source = "./modules/networking"

  name            = "vpc-gateway"
  cidr            = var.gateway_vpc_cidr
  azs             = var.azs
  public_subnets  = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnets = ["10.0.10.0/24", "10.0.11.0/24"]
  cluster_name    = "eks-gateway"
}

module "vpc_backend" {
  source = "./modules/networking"

  name            = "vpc-backend"
  cidr            = var.backend_vpc_cidr
  azs             = var.azs
  public_subnets  = ["10.1.0.0/24", "10.1.1.0/24"]
  private_subnets = ["10.1.10.0/24", "10.1.11.0/24"]
  cluster_name    = "eks-backend"
}

############################################
# VPC Peering + cross-VPC routing
############################################

module "peering" {
  source = "./modules/peering"

  requester_vpc_id          = module.vpc_gateway.vpc_id
  requester_cidr            = module.vpc_gateway.vpc_cidr
  requester_route_table_ids = concat(module.vpc_gateway.private_route_table_ids, [module.vpc_gateway.public_route_table_id])

  accepter_vpc_id          = module.vpc_backend.vpc_id
  accepter_cidr            = module.vpc_backend.vpc_cidr
  accepter_route_table_ids = concat(module.vpc_backend.private_route_table_ids, [module.vpc_backend.public_route_table_id])

  name = "gateway-to-backend"
}

############################################
# IAM (only eks-* / sentinel-* prefixes allowed)
############################################

module "iam_gateway" {
  source       = "./modules/iam"
  cluster_name = "eks-gateway"
}

module "iam_backend" {
  source       = "./modules/iam"
  cluster_name = "eks-backend"
}

############################################
# EKS clusters (one per VPC, private nodes)
############################################

module "eks_gateway" {
  source = "./modules/eks"

  cluster_name     = "eks-gateway"
  cluster_version  = var.cluster_version
  subnet_ids       = module.vpc_gateway.private_subnet_ids
  cluster_role_arn = module.iam_gateway.cluster_role_arn
  node_role_arn    = module.iam_gateway.node_role_arn
  instance_types   = var.node_instance_types
  desired_size     = var.node_desired_size
  min_size         = var.node_min_size
  max_size         = var.node_max_size
}

module "eks_backend" {
  source = "./modules/eks"

  cluster_name     = "eks-backend"
  cluster_version  = var.cluster_version
  subnet_ids       = module.vpc_backend.private_subnet_ids
  cluster_role_arn = module.iam_backend.cluster_role_arn
  node_role_arn    = module.iam_backend.node_role_arn
  instance_types   = var.node_instance_types
  desired_size     = var.node_desired_size
  min_size         = var.node_min_size
  max_size         = var.node_max_size
}

############################################
# Security: backend only reachable from the
# gateway VPC CIDR (HTTP + NodePort range)
############################################

resource "aws_security_group_rule" "backend_http_from_gateway" {
  description       = "HTTP from gateway VPC (internal ELB listener)"
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = [module.vpc_gateway.vpc_cidr]
  security_group_id = module.eks_backend.cluster_security_group_id
}

resource "aws_security_group_rule" "backend_nodeports_from_gateway" {
  description       = "NodePort range from gateway VPC for cross-VPC LB traffic"
  type              = "ingress"
  from_port         = 30000
  to_port           = 32768
  protocol          = "tcp"
  cidr_blocks       = [module.vpc_gateway.vpc_cidr]
  security_group_id = module.eks_backend.cluster_security_group_id
}
