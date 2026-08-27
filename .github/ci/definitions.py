"""Throwaway Dagster definitions used by `ct install` in the lint-test workflow.

A real code location bakes its definitions into its own image. The public image the `ci/` values point
at ships none that are loadable, so the workflow publishes this file as the `ci-definitions` ConfigMap
and the `ci/` values mount it as the location's Python package on PYTHONPATH.
"""

import dagster as dg


@dg.asset
def example_asset(context: dg.AssetExecutionContext) -> None:
    context.log.info("Hello from the chart-testing code location.")


defs = dg.Definitions(assets=[example_asset])
