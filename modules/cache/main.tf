# ElastiCache memcached for the fbctf demo (§3.4). One node is enough —
# the app's settings.ini takes MC_HOST[] as an array; we pass one endpoint.

resource "aws_elasticache_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.subnet_ids
}

resource "aws_elasticache_cluster" "this" {
  cluster_id      = var.name
  engine          = "memcached"
  node_type       = "cache.t3.micro"
  num_cache_nodes = 1
  port            = 11211

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [var.memcached_sg_id]
}
