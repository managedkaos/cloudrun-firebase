all: upgrade plan

plan:
	terraform plan

init:
	terraform $(@) -backend-config=backend.tfvars

reconfigure upgrade:
	terraform init -$(@) -backend-config=backend.tfvars

refresh validate fmt:
	terraform $(@)

apply:
	terraform apply -auto-approve

update:
	terraform get -update

output:
	terraform output

apikey:
	terraform output -raw api_key_value

orgid:
	gcloud organizations list

.PHONY: plan init reconfigure upgrade refresh validate fmt apply approve output
