import os
import random
import time
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.common.by import By
from functions.Functions import fill_element
from functions.Functions import scroll_to_element
from functions.Functions import click_js
from functions.Functions import wait_for_invisibility


def login_panel(driver, username="administrator", password="administrator"):
    driver.get(os.environ['CATALYST_SERVER'] + ":1443")
    try:
        driver.implicitly_wait(1)
        driver.find_element(By.XPATH, '//*[@id="login_page_v1"]//div/b/a').click()
        driver.implicitly_wait(10)
    except:
        pass
    finally:
        driver.implicitly_wait(10)
    WebDriverWait(driver, 10).until(EC.element_to_be_clickable((By.XPATH, '//*[@aria-label="Username"]')))
    fill_element(driver, '//*[@aria-label="Username"]', username)
    fill_element(driver, '//*[@aria-label="Password"]', password)
    click_js(driver, '//*[@id="q-app"]/div//main/div/form//button[contains(., "Sign In")]')
    driver.implicitly_wait(2)
    if len(driver.find_elements(By.XPATH, '//*[@id="footer"]//div//b/a[contains(., "GO TO NEW ADMIN PANEL")]')) > 0:
        driver.find_element(By.XPATH, '//*[@id="footer"]//div//b/a[contains(., "GO TO NEW ADMIN PANEL")]').click()
    driver.implicitly_wait(10)


def logout_panel(driver):
    driver.find_element(By.XPATH, '//*[@id="q-app"]//div/button[@aria-label="UserMenu"]').click()
    driver.find_element(By.XPATH, '/html/body//div[@class="q-list"]/div[2]').click()
    WebDriverWait(driver, 10).until(EC.visibility_of_element_located((By.XPATH, '//*[@id="login-title"]')))


def create_reseller(driver, resellername, contractname):
    print("Go to 'Reseller'...", end="")
    WebDriverWait(driver, 10).until(EC.element_to_be_clickable((By.XPATH, '//*[@id="q-app"]//div//aside//div//a[contains(., "Resellers")]')))
    driver.find_element(By.XPATH, '//*[@id="q-app"]//div//aside//div//a[contains(., "Resellers")]').click()
    print("OK")
    print("Try to create a new Reseller...", end="")
    driver.find_element(By.XPATH, '//*[@id="q-app"]/div//main//div/a[contains(., "Add")]').click()
    fill_element(driver, '//*[@id="q-app"]/div//main/form/div//label//div[contains(., "Contract")]/../div/input', contractname)
    WebDriverWait(driver, 10).until(EC.visibility_of_element_located((By.XPATH, '/html/body//div/div[@class="q-virtual-scroll__content"]/div[1]')))
    driver.find_element(By.XPATH, '/html/body//div/div[@class="q-virtual-scroll__content"]/div[1]').click()
    fill_element(driver, '//*[@id="q-app"]/div//main/form/div//label//div[contains(., "Name")]/../div/input',  resellername)
    driver.find_element(By.XPATH, '//*[@id="q-app"]//div//main//div/button[contains(., "Save")]').click()
    print("OK")


def delete_reseller(driver, reseller):
    print("Go to 'Reseller'...", end="")
    WebDriverWait(driver, 10).until(EC.element_to_be_clickable((By.XPATH, '//*[@id="q-app"]//div//aside//div//a[contains(., "Resellers")]')))
    driver.find_element(By.XPATH, '//*[@id="q-app"]//div//aside//div//a[contains(., "Resellers")]').click()
    print("OK")
    print("Try to delete Reseller...", end="")
    wait_for_invisibility(driver, '/html/body//div/main//div/label//div/input[contains(@class, "q-field--disabled")]')
    fill_element(driver, '/html/body//div/main//div/label//div/input', reseller)
    WebDriverWait(driver, 10).until(EC.visibility_of_element_located((By.XPATH, '//*[@id="q-app"]/div/div[2]/main/div[1]/div/div[1]/table/tbody/tr[1]/td[contains(., "' + reseller + '")]')))
    WebDriverWait(driver, 10).until(EC.element_to_be_clickable((By.XPATH, '//*[@id="q-app"]/div/div[2]/main/div[1]/div/div[1]/table/tbody/tr[1]/td[2]/button')))
    driver.find_element(By.XPATH, '//*[@id="q-app"]/div/div[2]/main/div[1]/div/div[1]/table/tbody/tr[1]/td[2]/button').click()
    WebDriverWait(driver, 10).until(EC.visibility_of_element_located((By.XPATH, '/html/body/div[4]/div/div')))
    driver.find_element(By.XPATH, '/html/body/div[4]/div/div').click()
    WebDriverWait(driver, 10).until(EC.visibility_of_element_located((By.XPATH, '/html/body/div[4]/div[2]/div/div[3]/button[2]')))
    driver.find_element(By.XPATH, '/html/body/div[4]/div[2]/div/div[3]/button[2]').click()
    wait_for_invisibility(driver, '/html/body//div[@class="q-virtual-scroll__content"]/div[1]')
    print("OK")


def create_reseller_contract(driver, contractname):
    print("Go to 'Contracts'...", end="")
    WebDriverWait(driver, 10).until(EC.element_to_be_clickable((By.XPATH, '//*[@id="q-app"]//div//aside//div//a[contains(., "Contracts")]')))
    driver.find_element(By.XPATH, '//*[@id="q-app"]//div//aside//div//a[contains(., "Contracts")]').click()
    print("OK")
    print("Try to create a new Reseller Contract...", end="")
    wait_for_invisibility(driver, '/html/body//div/main//div/label//div/input[contains(@class, "q-field--disabled")]')
    driver.find_element(By.XPATH, '//*[@id="q-app"]/div//main//div/button[contains(., "Add")]').click()
    driver.find_element(By.XPATH, '//*[@data-cy="aui-list-action-menu-item--contract-create-reseller"]').click()
    fill_element(driver, '//*[@id="q-app"]/div//main/form/div//label//div[contains(., "Contact")]/../div/input', "default")
    WebDriverWait(driver, 10).until(EC.visibility_of_element_located((By.XPATH, '/html/body/div//div[@class="q-virtual-scroll__content"]/div[1]')))
    time.sleep(1)
    driver.find_element(By.XPATH, '/html/body//div[@class="q-virtual-scroll__content"]/div[1]').click()
    wait_for_invisibility(driver, '/html/body//div[@class="q-virtual-scroll__content"]/div[1]')
    driver.find_element(By.XPATH, '//*[@id="q-app"]//div//main/form//div//label[contains(., "Status")]').click()
    WebDriverWait(driver, 10).until(EC.visibility_of_element_located((By.XPATH, '/html/body/div//div[@class="q-virtual-scroll__content"]/div[1]')))
    time.sleep(1)
    driver.find_element(By.XPATH, '/html/body//div[@class="q-virtual-scroll__content"]/div[1]').click()
    fill_element(driver, '//*[@id="q-app"]/div//main/form/div//label//div[contains(., "External")]/../div/input', contractname)
    driver.find_element(By.XPATH, '//*[@id="q-app"]//div//main/form//div//label[contains(., "Billing Profile")]').click()
    WebDriverWait(driver, 10).until(EC.visibility_of_element_located((By.XPATH, '/html/body/div//div[@class="q-virtual-scroll__content"]/div[1]')))
    time.sleep(1)
    driver.find_element(By.XPATH, '/html/body//div[@class="q-virtual-scroll__content"]/div[1]').click()
    driver.find_element(By.XPATH, '//*[@id="q-app"]/div//main//div/button[contains(., "Save")]').click()
    WebDriverWait(driver, 10).until(EC.visibility_of_element_located((By.XPATH, '/html/body//div[@role="alert"][contains(., "Contract created successfully")]')))
    print("OK")


def delete_reseller_contract(driver, contract):
    print("Go to 'Contracts'...", end="")
    WebDriverWait(driver, 10).until(EC.element_to_be_clickable((By.XPATH, '//*[@id="q-app"]//div//aside//div//a[contains(., "Contracts")]')))
    driver.find_element(By.XPATH, '//*[@id="q-app"]//div//aside//div//a[contains(., "Contracts")]').click()
    print("OK")
    print("Try to delete Reseller Contract...", end="")
    wait_for_invisibility(driver, '/html/body//div/main//div/label//div/input[contains(@class, "q-field--disabled")]')
    fill_element(driver, '/html/body//div/main//div/label//div/input', contract)
    WebDriverWait(driver, 10).until(EC.visibility_of_element_located((By.XPATH, '//*[@id="q-app"]/div/div[2]/main/div[1]/div/div[1]/table/tbody/tr/td[contains(., "' + contract + '")]')))
    WebDriverWait(driver, 10).until(EC.element_to_be_clickable((By.XPATH, '//*[@id="q-app"]/div/div[2]/main/div[1]/div/div[1]/table/tbody/tr[1]/td[2]/button')))
    driver.find_element(By.XPATH, '//*[@id="q-app"]/div/div[2]/main/div[1]/div/div[1]/table/tbody/tr[1]/td[2]/button').click()
    WebDriverWait(driver, 10).until(EC.visibility_of_element_located((By.XPATH, '/html/body/div[4]/div/div')))
    driver.find_element(By.XPATH, '/html/body/div[4]/div/div').click()
    WebDriverWait(driver, 10).until(EC.visibility_of_element_located((By.XPATH, '/html/body/div[4]/div[2]/div/div[3]/button[2]')))
    driver.find_element(By.XPATH, '/html/body/div[4]/div[2]/div/div[3]/button[2]').click()
    wait_for_invisibility(driver, '/html/body//div[@class="q-virtual-scroll__content"]/div[1]')
    print("OK")


def create_billing_profile(driver, billingname, billingrealname, reseller):
    print("Go to 'Billing Profiles'...", end="")
    WebDriverWait(driver, 10).until(EC.element_to_be_clickable((By.XPATH, '//*[@id="q-app"]//div//aside//div//a[contains(., "Billing Profile")]')))
    driver.find_element(By.XPATH, '//*[@id="q-app"]//div//aside//div//a[contains(., "Billing Profile")]').click()
    print("OK")
    print("Try to create a new Billing Profile...", end="")
    driver.find_element(By.XPATH, '//*[@id="q-app"]/div/div[2]/main/div/div[2]/div[1]/div[1]/a').click()
    fill_element(driver, '//*[@id="q-app"]/div/div[2]/main/form/div/div[1]/div/div[1]/div/div/div[1]/label/div[1]/div[1]/div[2]/div[1]/input', reseller)
    WebDriverWait(driver, 10).until(EC.visibility_of_element_located((By.XPATH, '/html/body//div/div[@class="q-virtual-scroll__content"]/div[1]')))
    driver.find_element(By.XPATH, '/html/body/div//div[@class="q-virtual-scroll__content"]/div[1]').click()
    fill_element(driver, '//*[@id="q-app"]/div/div[2]/main/form/div/div[1]/div/div[2]/div/label/div/div[1]/div/input', billingname)
    fill_element(driver, '//*[@id="q-app"]/div/div[2]/main/form/div/div[1]/div/div[3]/div/label/div/div[1]/div[1]/input', billingrealname)
    driver.find_element(By.XPATH, '//*[@id="q-app"]/div/div[2]/main/div/div[2]/button').click()
    print("OK")


def delete_billing_profile(driver, billingrealname):
    print("Go to 'Billing Profiles'...", end="")
    WebDriverWait(driver, 10).until(EC.element_to_be_clickable((By.XPATH, '//*[@id="q-app"]//div//aside//div//a[contains(., "Billing Profile")]')))
    driver.find_element(By.XPATH, '//*[@id="q-app"]//div//aside//div//a[contains(., "Billing Profile")]').click()
    print("OK")
    print("Try to delete Billing Profile...", end="")
    wait_for_invisibility(driver, '/html/body//div/main//div/label//div/input[contains(@class, "q-field--disabled")]')
    WebDriverWait(driver, 10).until(EC.element_to_be_clickable((By.XPATH, '/html/body//div/main//div/label//div/input')))
    fill_element(driver, '/html/body//div/main//div/label//div/input', billingrealname)
    wait_for_invisibility(driver, '//*[@id="q-app"]/div//main//div/table/thead/tr[2]/th/div[@role="progressbar"]')
    WebDriverWait(driver, 10).until(EC.element_to_be_clickable((By.XPATH, '//*[@id="q-app"]/div/div[2]/main/div[1]/div/div[1]/table/tbody/tr[1]/td[2]/button')))
    driver.find_element(By.XPATH, '//*[@id="q-app"]/div/div[2]/main/div[1]/div/div[1]/table/tbody/tr[1]/td[2]/button').click()
    WebDriverWait(driver, 10).until(EC.visibility_of_element_located((By.XPATH, '/html/body/div[4]/div/div[2]')))
    driver.find_element(By.XPATH, '/html/body/div[4]/div/div[2]').click()
    WebDriverWait(driver, 10).until(EC.visibility_of_element_located((By.XPATH, '/html/body/div[4]/div[2]/div/div[3]/button[2]')))
    driver.find_element(By.XPATH, '/html/body/div[4]/div[2]/div/div[3]/button[2]').click()
    wait_for_invisibility(driver, '/html/body//div[@class="q-virtual-scroll__content"]/div[1]')
    print("OK")
