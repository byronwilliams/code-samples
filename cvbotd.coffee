#!/usr/bin/env node

fs            = (require "fs")
path          = (require "path")
child_process = (require "child_process")
crypto        = (require "crypto")
https         = (require "https")
url           = (require "url")

mkdirp        = (require "mkdirp")

Q            = (require "q")
express      = (require "express")
ElasticSearchClient = require('elasticsearchclient');

STATUS_CODES = (require "./status_codes")
CVTokenizer  = (require "./cvtokenizer")
CVParser     = (require "./cvparser")

app = express()
app.use express.bodyParser()

PROC_OPTS =
  maxBuffer:8000*1024

ENV = {}

apiUrl = (env,path) ->
  opts = url.parse url.parse env.endpoint + path
  opts.rejectUnauthorized = false
  opts.headers =
    "Auth": "CVBOTD:password"

  opts

class CVBot
  # 1. Accept HTTP connection with TaskId
  constructor: (@taskId) ->
    @env = ENV

# 1. Receive CV Processing Task
# 2. Get Environment Details
# 3. Get Document to Process
# 4. Convert Document to Image
# 4.1 Save Image back to API
# 5. Convert Document to Text
# 5.1 Store CV in ElasticSearch
# 5.2 Parse CV for Sections
# 5.3 Parse Sections for Tokens
# 5.4 Extract Tokens
# 5.5 Return tokens

  run: () ->
    d = Q.defer()
    @getTask()
      .then (@task) =>
        console.log @task
        @updateStatus STATUS_CODES.STARTED
      .then (response) =>
        @getDocumentType()
      .then (@documentType) =>
        @mkdirRecursive @genOutFilePath()
      .then () =>
        @convertDocumentToImage()
        # .then (imgData) =>
        console.log "converted document to image"
        #   @saveImageToDB imgData
      .then () =>
        @convertDocumentToText().then (docText) =>
          console.log "convertedToText"
          @saveTextToElasticSearch(docText).then () =>
            console.log "converted document to text"
      .then () =>
        d.resolve true
      # .then (@rawText) =>
      #   fs.unlinkSync @outFilePath
      #   @cleanText()
      #   @
      #   d.resolve @parse()
    d.promise

  getTask: () =>
    d = Q.defer()

    opts = apiUrl @env, "/tasks/" + @taskId
    req = https.request opts, (res) ->
      res.setEncoding "utf8"
      res.on "data", (data) ->
        console.log data
        if res.statusCode isnt 200
          d.reject {}
        else
          d.resolve JSON.parse data
    req.end()

    req.on "error", (e) ->
      console.log e
      d.reject e

    d.promise

  # 2. Update Database to say TaskId has been started
  updateStatus: (code,msg) ->
    d = Q.defer()
    d.resolve code.code + ": " + code.msg
    d.promise
#    console.log line

  # 3. Find out which document type it is
  getDocumentType: () =>
    d = Q.defer()

    parts = @task.filepath.split "."
    if parts[parts.length-1] in ["docx","doc","pdf"]
      d.resolve parts[parts.length-1]
    else if @task.mimetype
      switch @task.mimetype
        when "application/pdf" then d.resolve "pdf"
        when "application/msword" then d.resolve "doc"
        when "application/vnd.openxmlformats-officedocument.wordprocessingml.document" then d.resolve "docx"
        else d.reject "unknown document type"
    else
      d.reject "unknown document type"

    d.promise

  genOutFilePath: () ->
    p = @task.filepath.split("/")
    fn = p[p.length-1]
    @env.paths.storage + "cvs/" + fn[0] + "/" + fn[1] + "/" + fn

  mkdirRecursive: () ->
    d = Q.defer()

    p = @genOutFilePath()

    fs.exists p, (exists) ->
      if exists
        d.resolve true
      else
        mkdirp p, (err) ->
          if err
            console.log err
            d.reject err
          else
            console.log true
            d.resolve true
    d.promise

  convertDocumentToImage: () =>
    d = Q.defer()
    proc = null

    switch @documentType
      when "pdf"  then d.resolve @convertPdfToImage()
      when "doc"  then d.resolve @convertDocToImage()
      when "docx" then d.resolve @convertDocToImage()
      else d.reject "unknown document type"

    d.promise

  # 4. Convert document to text
  convertDocumentToText: () =>
    d = Q.defer()
    proc = null

    switch @documentType
      when "pdf"  then proc = @convertPdfToText()
      when "doc"  then proc = @convertDocToText()
      when "docx" then proc = @convertDocToText()

    if proc
      proc.then (fileName) =>
        fs.readFile fileName, "utf-8", (err, data) =>
          d.resolve data
      proc.fail (err) ->
        d.reject err
    else
      d.reject "unknown document type"

    d.promise

  convertPdfToText: () =>
    d = Q.defer()

    newFilename = @genOutFilePath() + ".txt"
    cmd = ["pdftotext","-layout","-nopgbrk",@task.filepath,newFilename].join " "
    child_process.exec cmd, PROC_OPTS, (err,stdout,stderr) ->
      d.resolve newFilename
    d.promise

  convertPdfToImage: (filepath=@task.filepath) =>
    newFilename = @genOutFilePath() + ".png"
    outStream   = fs.createWriteStream newFilename

    d = Q.defer()

    cmd = ["pdftoppm","-gray","-png",filepath]

    pdftoppm = child_process.spawn cmd[0], cmd[1..]
    pdftoppm.stdout.on "data", (data) ->
      outStream.write data
    pdftoppm.on "close", (code) ->
      outStream.end () ->
        d.resolve true

    d.promise

  convertDocToImage: () =>
    d = new Date()
    tmp_filename = "/tmp/" + crypto.createHash("sha1").update("" + d).digest("hex")

    d = Q.defer()

    cmd = ["unoconv","-f","pdf","-o",tmp_filename,@task.filepath].join " "

    unoconv = child_process.exec cmd, PROC_OPTS, (error,stdout,stderr) =>
      d.resolve @convertPdfToImage tmp_filename

    d.promise

  convertDocToText: () =>
    newFilename = @genOutFilePath() + ".txt"
    cmd = ["unoconv","-f","txt","-o",newFilename,@task.filepath].join " "

    d = Q.defer()

    unoconv = child_process.exec cmd, PROC_OPTS, (error,stdout,stderr) =>
      d.resolve newFilename

    d.promise

  saveImageToDB: (imgData) =>
    buf = new Buffer imgData

    doc =
      filedata: "mimetype:image/png;" + buf.toString("base64")

    console.log doc.filedata[0..50]

  saveTextToElasticSearch: (text) =>
    d = Q.defer()

    esCfg = @env.elasticsearch.default
    host =
      host: esCfg.hosts[0]
      port: 9200

    serverOptions =
      hosts: [host]

    docId = @task.doc_id

    doc =
      cvtext: text
      email: ""
      name: ""

    es = new ElasticSearchClient serverOptions
    res = es.index(esCfg.index, "cv", doc, docId).on "data", (data) ->
      console.log data
    .on "done", (data) ->
      d.resolve data
    .exec()

    d.promise

  # 5. Trim/Strip all lines, remove unknown characters
  cleanText: () =>
    @cleanedText = ""

    for line in @rawText.split "\n"
      txt = line.trim()
      txt = txt.replace(/\t/g," ")
      @cleanedText += txt + "\n"

  # 6. Parse text document
  parse: () =>
    parser = new CVParser()
    doc    = parser.parse @cleanedText

    doc

module.exports = CVBot

# bot = new CVBot ENV,1
# bot.run()
# bot1 = new CVBot ENV,2
# bot1.run()
# bot2 = new CVBot ENV,3
# bot2.run()
# bot3 = new CVBot ENV,4
# bot3.run()

#module.exports = CVBot


# app.post "/", (req,res) ->
#   data = req.body
#   console.log "Accepted File: " + data.filename
#   b64_file = data.filedata.substring data.filedata.indexOf(",")+1
#   tmp_filename = crypto.createHash("sha1").update(b64_file).digest "hex"
#   tmp_filename_path = "/tmp/cvbotd-" + tmp_filename

#   fs.writeFile tmp_filename_path, b64_file, "base64", (err) ->
#     if err
#       console.log err

#   cvbot = new CVBot tmp_filename_path, data.mimetype
#   cvbot.run().then (rdoc) =>
#     fs.unlinkSync tmp_filename_path
#     res.set "Content-Type", "application/json"
#     res.json 200, rdoc
#     console.log "Completed Request"

# app.listen 9123
