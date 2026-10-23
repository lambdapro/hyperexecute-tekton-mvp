"""Minimal Selenium tests that HyperExecute runs on its own VMs."""
from selenium.webdriver.common.by import By

APP_URL = "https://lambdatest.github.io/sample-todo-app/"


def test_page_title(driver):
    driver.get(APP_URL)
    assert "Sample page" in driver.title


def test_add_todo(driver):
    driver.get(APP_URL)
    driver.find_element(By.ID, "sampletodotext").send_keys("Run on HyperExecute via Tekton")
    driver.find_element(By.ID, "addbutton").click()
    items = driver.find_elements(By.CSS_SELECTOR, "ul.list-unstyled li")
    assert items[-1].text == "Run on HyperExecute via Tekton"


def test_check_items(driver):
    driver.get(APP_URL)
    driver.find_element(By.NAME, "li1").click()
    driver.find_element(By.NAME, "li2").click()
    remaining = driver.find_element(By.CSS_SELECTOR, "span.ng-binding").text
    assert "3 of 5 remaining" in remaining
