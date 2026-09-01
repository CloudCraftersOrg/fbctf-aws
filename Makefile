# ENV selects the root under environments/: demo (the live app, default),
# artifacts (the persistent bucket), or sqlmod (SQL Server for the Aurora job).
ENV ?= demo
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

# The app runs an EOL OS — destroy after every demo session.
destroy:
	terraform -chdir=$(TF_DIR) destroy

fmt:
	terraform fmt -recursive

validate:
	terraform -chdir=$(TF_DIR) validate
