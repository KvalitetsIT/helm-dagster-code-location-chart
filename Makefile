all: lint docs

clean-locks:
	find ./charts -maxdepth 2 -name "Chart.lock" -delete

lint: clean-locks
	docker run --rm --name chart-testing -w /data -v $(PWD):/data quay.io/helmpack/chart-testing:v3.14.0 \
		sh -c "helm repo add kvalitetsit https://raw.githubusercontent.com/KvalitetsIT/helm-repo/master/ && ct lint --config /data/ct.yaml"

docs:
	docker run --rm --name helm-docs -v "$(PWD):/helm-docs" jnorwood/helm-docs:v1.14.2 --sort-values-order file --chart-to-generate charts/dagster-code-location --output-file README.md
