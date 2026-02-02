all: upgrade plan

plan:
	terraform plan

init:
	terraform $(@) -backend-config="bucket=$(TERRAFORM_STATE_BUCKET)"

reconfigure upgrade:
	terraform init -$(@) -backend-config="bucket=$(TERRAFORM_STATE_BUCKET)"

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

.PHONY: plan init reconfigure upgrade refresh validate fmt apply approve output
