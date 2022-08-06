import os
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.firefox.options import Options

# env constants
BROWSER_BIN = r'/usr/bin/firefox-developer-edition'
FILE_NAME = 'commits.txt'

options = Options()
options.binary_location = BROWSER_BIN
options.headless = True
driver = webdriver.Firefox(options=options)

url = input("Enter bulletin page URL: ")
driver.get(url)

main_element = driver.find_element(By.CLASS_NAME, 'devsite-article')
table_containers = main_element.find_elements(By.CLASS_NAME, 'devsite-table-wrapper')
tables = []
for element in table_containers:
    tables.append(element.find_element(By.TAG_NAME, 'table').find_element(By.TAG_NAME, 'tbody'))
title_elements = main_element.find_elements(By.TAG_NAME, 'h3')
titles = []
for element in title_elements:
    titles.append(element.get_attribute('data-text'))

file = open(FILE_NAME, "w")
for table in tables:
    rows = table.find_elements(By.TAG_NAME, 'tr')
    rows.pop(0)
    title_print = ""
    if (len(titles) > 0):
        title_print = titles.pop(0) + ":"
    else:
        title_print = "No title:"
    file.write(title_print + "\n")
    print(title_print)
    for row in rows:
        link_elements = row.find_elements(By.TAG_NAME, 'td')[1].find_elements(By.TAG_NAME, 'a')
        for element in link_elements:
            link = element.get_attribute('href')
            if (link.find('#asterisk') != -1):
                continue
            file.write(link + "\n")
            print(link)
    file.write("\n")
    print()
file.close()
driver.close()
