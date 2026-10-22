LAMBDA_SRC = lambda/api_test_client/index.py
LAMBDA_ZIP = lambda/api_test_client.zip

.PHONY: all fmt validate docs lambda/zip lambda/check

all: fmt validate lambda/zip docs

fmt:
	terraform fmt -recursive

validate:
	terraform init -backend=false -input=false >/dev/null
	terraform validate

docs:
	terraform-docs markdown table --lockfile=false --output-file README.md --output-mode inject .

lambda/zip:
	python3 scripts/build_lambda_zip.py $(LAMBDA_SRC) $(LAMBDA_ZIP)

lambda/check:
	python3 scripts/build_lambda_zip.py $(LAMBDA_SRC) $(LAMBDA_ZIP).check
	@cmp -s $(LAMBDA_ZIP) $(LAMBDA_ZIP).check || { rm -f $(LAMBDA_ZIP).check; echo "$(LAMBDA_ZIP) is out of date: run make lambda/zip and commit it"; exit 1; }
	@rm -f $(LAMBDA_ZIP).check
