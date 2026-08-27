# Non-secret runtime configuration under /fbctf/* — read by both tiers'
# user-data (the instance roles allow ssm:GetParameter on /fbctf/*).
# /fbctf/nlb_dns is added by the NLB module in Phase 5.

resource "aws_ssm_parameter" "this" {
  for_each = var.parameters

  name  = "/fbctf/${each.key}"
  type  = "String"
  value = each.value
}
