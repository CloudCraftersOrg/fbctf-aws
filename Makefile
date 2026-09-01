# ENV selects the root under environments/ (sqlmod | discovery-collector | artifacts).
ENV ?= sqlmod
AWS_PROFILE ?= cloudcrafters-sandbox
TF_DIR = environments/$(ENV)

export AWS_PROFILE

.PHONY: init plan apply destroy fmt validate

init:
	terraform -chdir=$(TF_DIR) init

plan:
	terraform -chdir=$(TF_DIR) plan

apply:
	terraform -chdir=$(TF_DIR) apply

destroy:
	terraform -chdir=$(TF_DIR) destroy

fmt:
	terraform fmt -recursive

validate:
	terraform -chdir=$(TF_DIR) validate
