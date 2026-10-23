"""Shared fixtures for the Selenium tests that HyperExecute runs on its own VMs.

Credentials come from LT_USERNAME / LT_ACCESS_KEY, which the HyperExecute
CLI propagates to the job (the Tekton Task reads them from a k8s Secret).
"""
import os

import pytest
from selenium import webdriver

HUB = "https://{u}:{k}@hub.lambdatest.com/wd/hub"


@pytest.fixture
def driver(request):
    opts = webdriver.ChromeOptions()
    opts.set_capability("browserName", "Chrome")
    opts.set_capability("browserVersion", "latest")
    opts.set_capability(
        "LT:Options",
        {
            "platformName": "Windows 11",
            "build": os.getenv("BUILD_NAME", "tekton-hyperexecute-mvp"),
            "name": request.node.name,
            "w3c": True,
        },
    )
    drv = webdriver.Remote(
        command_executor=HUB.format(
            u=os.environ["LT_USERNAME"], k=os.environ["LT_ACCESS_KEY"]
        ),
        options=opts,
    )
    yield drv
    status = "failed" if request.node.rep_call.failed else "passed"
    drv.execute_script(f"lambda-status={status}")
    drv.quit()


@pytest.hookimpl(tryfirst=True, hookwrapper=True)
def pytest_runtest_makereport(item, call):
    outcome = yield
    rep = outcome.get_result()
    setattr(item, "rep_" + rep.when, rep)
