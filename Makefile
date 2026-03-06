PROJECT_ID=onelead-487402
BUCKET=onelead-tf-state
GITHUB_REPO=codemk12/cicd-template
REGION=australia-southeast1
SA_EMAIL=github-actions-deployer@$(PROJECT_ID).iam.gserviceaccount.com

# ── Setup (run once locally) ─────────────────────────────────────────
setup: setup-apis setup-bucket setup-bootstrap setup-iam setup-secrets
	@echo "Setup complete"

setup-apis:
	gcloud services enable run.googleapis.com iam.googleapis.com \
		iamcredentials.googleapis.com containerregistry.googleapis.com \
		--project=$(PROJECT_ID)

setup-bucket:
	gsutil mb -p $(PROJECT_ID) -l $(REGION) gs://$(BUCKET) 2>/dev/null || true
	gsutil versioning set on gs://$(BUCKET)

setup-bootstrap:
	cd terraform/bootstrap && terraform init -reconfigure \
		-backend-config="bucket=$(BUCKET)" \
		-backend-config="prefix=state/bootstrap"
	cd terraform/bootstrap && terraform apply -auto-approve \
		-var="project_id=$(PROJECT_ID)" \
		-var="github_repo=$(GITHUB_REPO)"

setup-iam:
	gcloud projects add-iam-policy-binding $(PROJECT_ID) \
		--member="serviceAccount:$(SA_EMAIL)" \
		--role="roles/run.admin" --quiet
	gcloud projects add-iam-policy-binding $(PROJECT_ID) \
		--member="serviceAccount:$(SA_EMAIL)" \
		--role="roles/artifactregistry.writer" --quiet
	gcloud projects add-iam-policy-binding $(PROJECT_ID) \
		--member="serviceAccount:$(SA_EMAIL)" \
		--role="roles/storage.admin" --quiet
	gcloud projects add-iam-policy-binding $(PROJECT_ID) \
		--member="serviceAccount:$(SA_EMAIL)" \
		--role="roles/iam.serviceAccountUser" --quiet

setup-secrets:
	$(eval WIF_PROVIDER := $(shell gcloud iam workload-identity-pools providers describe github-provider \
		--workload-identity-pool=github-actions-pool --location=global \
		--project=$(PROJECT_ID) --format="value(name)"))
	gh secret set GCP_WIF_PROVIDER --repo $(GITHUB_REPO) --body "$(WIF_PROVIDER)"
	gh secret set GCP_SA_EMAIL --repo $(GITHUB_REPO) --body "$(SA_EMAIL)"

# ── Deploy (used by CI/CD) ───────────────────────────────────────────
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
		-var="environment=$(ENV)"

# ── Teardown (destroy everything) ────────────────────────────────────
teardown: teardown-services teardown-bootstrap teardown-images teardown-bucket teardown-iam
	@echo "Teardown complete"

teardown-services:
	@for env in dev uat prod; do \
		echo "Destroying $$env..."; \
		cd terraform && terraform init -reconfigure \
			-backend-config="bucket=$(BUCKET)" \
			-backend-config="prefix=state/$$env" 2>/dev/null; \
		terraform destroy -auto-approve \
			-var="project_id=$(PROJECT_ID)" \
			-var="service_name=fastapi-$$env" \
			-var="image_url=gcr.io/$(PROJECT_ID)/fastapi:$$env" \
			-var="environment=$$env" 2>/dev/null || true; \
		cd ..; \
	done

teardown-bootstrap:
	cd terraform/bootstrap && terraform init -reconfigure \
		-backend-config="bucket=$(BUCKET)" \
		-backend-config="prefix=state/bootstrap" 2>/dev/null
	cd terraform/bootstrap && terraform destroy -auto-approve \
		-var="project_id=$(PROJECT_ID)" \
		-var="github_repo=$(GITHUB_REPO)" 2>/dev/null || true

teardown-images:
	@for digest in $$(gcloud container images list-tags gcr.io/$(PROJECT_ID)/fastapi --format="get(digest)" 2>/dev/null); do \
		gcloud container images delete "gcr.io/$(PROJECT_ID)/fastapi@$$digest" --force-delete-tags --quiet 2>/dev/null || true; \
	done

teardown-bucket:
	gsutil rm -r gs://$(BUCKET) 2>/dev/null || true

teardown-iam:
	@for role in roles/run.admin roles/artifactregistry.writer roles/storage.admin roles/iam.serviceAccountUser; do \
		gcloud projects remove-iam-policy-binding $(PROJECT_ID) \
			--member="serviceAccount:$(SA_EMAIL)" \
			--role="$$role" --quiet 2>/dev/null || true; \
	done
