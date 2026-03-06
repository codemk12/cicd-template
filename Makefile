PROJECT_ID=onelead-487402
BUCKET=onelead-tf-state
GITHUB_REPO=codemk12/cicd-template
REGION=australia-southeast1

deploy:
	docker build --platform linux/amd64 -t gcr.io/$(PROJECT_ID)/fastapi:$(ENV) .
	docker push gcr.io/$(PROJECT_ID)/fastapi:$(ENV)
	cd terraform && terraform init -reconfigure \
		-backend-config="bucket=$(BUCKET)" \
		-backend-config="prefix=state/$(ENV)"
	cd terraform && terraform apply -auto-approve \
		-var="project_id=$(PROJECT_ID)" \
		-var="service_name=fastapi-$(ENV)" \
		-var="image_url=gcr.io/$(PROJECT_ID)/fastapi:$(ENV)" \
		-var="environment=$(ENV)" \
		-var="github_repo=$(GITHUB_REPO)"
