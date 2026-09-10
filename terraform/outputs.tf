output "gateway_vpc_id" {
  value = module.vpc_gateway.vpc_id
}

output "backend_vpc_id" {
  value = module.vpc_backend.vpc_id
}

output "peering_connection_id" {
  value = module.peering.peering_connection_id
}

output "eks_gateway_name" {
  value = module.eks_gateway.cluster_name
}

output "eks_backend_name" {
  value = module.eks_backend.cluster_name
}

output "region" {
  value = var.region
}
