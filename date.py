#!/bin/python
import subprocess
from datetime import datetime

def get_password_expiry_from_chage(gdcuser):
  try:
    chage = subprocess.Popen(('chage', '-l', gdcuser), stdout=subprocess.PIPE)
    grep = subprocess.Popen(('grep', 'Password expires'), stdin=chage.stdout, stdout=subprocess.PIPE)
    cut = subprocess.Popen('cut -d : -f2'.split(), stdin=grep.stdout, stdout=subprocess.PIPE)
    output = cut.communicate()[0].strip()
    return output if output != 'never' else None
  except subprocess.CalledProcessError as e:
    return None

def main():
  # Check user on server
  grep_account = subprocess.Popen(('grep', 'gdcuser', '/etc/passwd'), stdout=subprocess.PIPE)
  cut_account =  subprocess.Popen('cut -d : -f1'.split(), stdin=grep_account.stdout,  stdout=subprocess.PIPE)
  output_account = cut_account.communicate()[0].strip()

  # Check passwd user expire
  chage_date = get_password_expiry_from_chage(output_account)
  expiry_date = datetime.strptime(chage_date, '%b %d, %Y')
  today = datetime.now()
  expiry_date = abs((expiry_date - today).days)
  if expiry_date < 5:
     print("Critical user: gdcuser password expires after {} days. Please check end change password ".format(expiry_date))
  else:
     return None

main()
