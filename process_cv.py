#!/usr/bin/env python

import gearman
import requests
import subprocess
import tempfile
import os
import base64
import json
import shutil
import time
import argparse

HTTPAUTH = requests.auth.HTTPDigestAuth("","")

ENV = {
  "local": ['localhost:4730'],
  "staging": [],
  "production": []
}

def timeout(cmd, timeout=30):
  c = subprocess.Popen(cmd)

  t = 0

  while t < timeout and c.poll() is None:
    time.sleep(0.25)
    t+=0.25

  if c.poll() is None:
    c.terminate()
    returncode = -1
  else:
    returncode = c.poll()

  return returncode

def get_task(taskUrl):
  if "staging" in taskUrl:
    r = requests.get(taskUrl,verify=False,auth=HTTPAUTH)
  else:
    r = requests.get(taskUrl,verify=False)

  return json.loads(r.text)

def pdf_to_text(srcPath):
  text = ""
  print("pdf_to_text")
  inputDir, newFilename = os.path.split(srcPath)

  with tempfile.NamedTemporaryFile(prefix="process_cv",suffix=newFilename) as f:
    cmd = ["pdftotext","-layout","-nopgbrk",srcPath,f.name]
    subprocess.call(cmd)

    text = f.read()

  return text

def unoconv_doc_to_text(srcPath):
  text = ""
  print(srcPath)
  inputDir, newFilename = os.path.split(srcPath)

  with tempfile.NamedTemporaryFile(prefix="process_cv",suffix=newFilename) as f:
    cmd = ["unoconv","-T","5","-f","txt","-o",f.name,srcPath]
    print(cmd)
    timeout(cmd,10)

    text = f.read()

  return text

def unoconv_doc_to_img_base64(srcPath):
  result = None

  inputDir, newFilename = os.path.split(srcPath)

  with tempfile.NamedTemporaryFile(prefix="process_cv",suffix=newFilename) as f:
    cmd = ["unoconv","-T","5","-f","pdf","-o",f.name,srcPath]
    #subprocess.call(cmd)
    timeout(cmd,10)

    result = pdf_to_img_base64(f.name)

  return result

def pdf_to_img_base64(srcPath):
  result = None

  outDir = tempfile.mkdtemp(prefix="process_cv")
  outPrefix = outDir + "/img"

  cmd = ["pdftoppm","-gray","-png",srcPath,outPrefix]
  subprocess.call(cmd)

  with tempfile.NamedTemporaryFile(prefix="process_cv") as f:
    cmd = ["montage", "-border","1",
                      "-tile","1x",
                      "-geometry","750x",
                      outPrefix + "*",f.name]
    #subprocess.call(cmd)
    timeout(cmd,10)

    result = base64.b64encode(f.read())

  shutil.rmtree(outDir)

  return result

def process_cv(taskUrl):
  task = get_task(taskUrl)
  endpoint = task["env"]["endpoint"]

  text = ""
  img_base64 = None

  if task["mimetype"] == "application/pdf":
    img_base64 = pdf_to_img_base64(task["filepath"])
    text       = pdf_to_text(task["filepath"])
  elif task["mimetype"] in ["application/msword","application/vnd.openxmlformats-officedocument.wordprocessingml.document"]:
    text       = unoconv_doc_to_text(task["filepath"])
    img_base64 = unoconv_doc_to_img_base64(task["filepath"])


  post_data = {
    "doc_id": task["doc_id"],
    "filename": "cvimg",
    "mimetype": "image/png",
    "text": text,
    "img_base64": img_base64
  }

  payload = json.dumps(post_data)

  if "staging" in endpoint:
    is_posted = requests.post(endpoint+"/tasks/process_cv",data=payload,verify=False,auth=HTTPAUTH)
  else:
    is_posted = requests.post(endpoint+"/tasks/process_cv",data=payload,verify=False)
  return json.dumps(is_posted.json)

def gearman_process_cv(gearman_worker, gearman_job):
  taskUrl = gearman_job.data
  try:
    process_cv(taskUrl)
  except Exception as e:
    print(e)

  return ""

class ProcessCVTask(gearman.GearmanWorker):
  def on_job_execute(self, current_job):
    print("Job started")
    return super(ProcessCVTask, self).on_job_execute(current_job)

  def on_job_exception(self, current_job, exc_info):
    print("Job failed")
    return super(ProcessCVTask, self).on_job_exception(current_job, exc_info)

  def on_job_complete(self, current_job, job_result):
    print("Job complete")
    return super(ProcessCVTask, self).send_job_complete(current_job, job_result)

  def after_poll(self, any_activity):
    # Return True if you want to continue polling, replaces callback_fxn
    return True

def run(env):
  gm_worker = ProcessCVTask(ENV[env])

  gm_worker.register_task("process_cv", gearman_process_cv)

  # Enter our work loop and call gm_worker.after_poll() after each time we timeout/see socket activity
  gm_worker.work()

if __name__ == "__main__":
  parser = argparse.ArgumentParser(description="Processor")
  parser.add_argument("--env", help="Environment to run",required=True,choices=("local","staging","production"))
  args = parser.parse_args()

  run(args.env)
