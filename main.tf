module "vpc" {
  source = "./module/vpc"

  project_name = var.project_name

  vpc_cidr            = var.vpc_cidr
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr
  availability_zone   = var.availability_zone

  public_subnet_2_cidr  = var.public_subnet_2_cidr
  private_subnet_2_cidr = var.private_subnet_2_cidr
  availability_zone_2   = var.availability_zone_2
}


module "keypair" {
  source = "./module/keypair"

  project_name = var.project_name
}


module "platform_alb" {
  source = "./module/platform-alb"

  project_name = var.project_name
  vpc_id       = module.vpc.vpc_id

  public_subnet_ids = [
    module.vpc.public_subnet_id,
    module.vpc.public_subnet_2_id
  ]

  domain_name = "ferdeve.fit"
}


module "jenkins" {
  source = "./module/jenkins"

  project_name = var.project_name
  vpc_id       = module.vpc.vpc_id
  subnet_id    = module.vpc.public_subnet_id
  key_name     = module.keypair.key_name

  allowed_cidr = var.allowed_cidr

  platform_alb_security_group_id = module.platform_alb.security_group_id
}


module "nexus" {
  source = "./module/nexus"

  project_name = var.project_name
  vpc_id       = module.vpc.vpc_id
  subnet_id    = module.vpc.public_subnet_id
  key_name     = module.keypair.key_name

  platform_alb_security_group_id = module.platform_alb.security_group_id
}


# ============================================================
# JENKINS HOST-BASED ROUTING
# ============================================================

resource "aws_lb_listener_rule" "jenkins" {
  listener_arn = module.platform_alb.listener_arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = module.jenkins.target_group_arn
  }

  condition {
    host_header {
      values = ["jenkins.ferdeve.fit"]
    }
  }
}


# ============================================================
# NEXUS HOST-BASED ROUTING
# ============================================================

resource "aws_lb_listener_rule" "nexus" {
  listener_arn = module.platform_alb.listener_arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = module.nexus.target_group_arn
  }

  condition {
    host_header {
      values = ["nexus.ferdeve.fit"]
    }
  }
}


# ============================================================
# JENKINS DNS
# ============================================================

resource "aws_route53_record" "jenkins" {
  zone_id = module.platform_alb.hosted_zone_id
  name    = "jenkins.ferdeve.fit"
  type    = "A"

  alias {
    name                   = module.platform_alb.alb_dns_name
    zone_id                = module.platform_alb.alb_zone_id
    evaluate_target_health = true
  }
}


# ============================================================
# NEXUS DNS
# ============================================================

resource "aws_route53_record" "nexus" {
  zone_id = module.platform_alb.hosted_zone_id
  name    = "nexus.ferdeve.fit"
  type    = "A"

  alias {
    name                   = module.platform_alb.alb_dns_name
    zone_id                = module.platform_alb.alb_zone_id
    evaluate_target_health = true
  }
}

module "sonarqube" {
  source = "./module/sonarqube"

  project_name = var.project_name
  vpc_id       = module.vpc.vpc_id
  subnet_id    = module.vpc.public_subnet_id

  platform_alb_security_group_id = module.platform_alb.security_group_id
}

# ============================================================
# SONARQUBE HOST-BASED ROUTING
# ============================================================

resource "aws_lb_listener_rule" "sonarqube" {
  listener_arn = module.platform_alb.listener_arn
  priority     = 30

  action {
    type             = "forward"
    target_group_arn = module.sonarqube.target_group_arn
  }

  condition {
    host_header {
      values = ["sonarqube.ferdeve.fit"]
    }
  }
}

# ============================================================
# SONARQUBE DNS
# ============================================================

resource "aws_route53_record" "sonarqube" {
  zone_id = module.platform_alb.hosted_zone_id
  name    = "sonarqube.ferdeve.fit"
  type    = "A"

  alias {
    name                   = module.platform_alb.alb_dns_name
    zone_id                = module.platform_alb.alb_zone_id
    evaluate_target_health = true
  }
}