restify = require "restify"
rethinkdb = require "rethinkdb"
uuid = require "node-uuid"
zmq = require "zmq"
fs = require "fs"

gm = require "gm"
Q = require "q"

zmqsock = zmq.socket "push"
zmqsock.connect "tcp://127.0.0.1:77620"

connection = null

dbconn = rethinkdb.connect
  host: "localhost"
  port: 28015
, (err, conn) ->
  if err
    throw err
  else
    connection = conn
    connection.use "bumblebee"

pushUpdate = () ->
  zmqsock.send "regenerate"

class Handler
  constructor: (@route, @methods) ->

  get: ->
  put: ->
  del: ->
  post: ->
  patch: ->


server = restify.createServer
  name: "ByPress Admin"
server.use restify.bodyParser()
server.use restify.fullResponse()
server.use restify.gzipResponse()
server.use restify.queryParser()


ROUTE_PREFIX = "/api"

curTime = () ->
  parseInt(new Date().getTime() / 1000)

registerOne = (route, method, cb) ->
  console.log [method,ROUTE_PREFIX+route].join " "
  server[method](ROUTE_PREFIX+route,cb)

register = (handler) ->
  registerOne handler.route, method.toLowerCase(), handler[method.toLowerCase()] for method in handler.methods
#  registerOne route, method.toLowerCase(), cb for method in methods


class SiteListHandler extends Handler
  db = rethinkdb.table "sites"

  get: (req,res,next) ->
    siteId = req.headers["x-bumblebee-site-id"]
#    .filter({siteId:siteId}) filter by siteit?
    db.pluck("id","name").run connection, (err,result) ->
      if err
        res.send []
      else
        result.toArray (err,results) ->
          res.send results
      next()

  put: (req,res,next) ->
    item =
      name: "unnamed site"
      isActive: false
    db.insert(item).run connection, (err, result) ->
      db.get(result.generated_keys[0]).run connection, (err,result) ->
        res.send result
        #pushUpdate()
        next()


class SiteHandler extends Handler
  table = rethinkdb.table "sites"

  get: (req,res,next) ->
    console.log req.params.id
    table.get(req.params.id).run connection, (err,result) ->
      if err
        res.send 404
      else
        res.send result
      next()


  put: (req,res,next) ->
    console.log "PUT"

    site = JSON.parse(req.body)

    table.get(site.id).replace(site).run connection, (err, result) ->
      table.get(site.id).run connection, (err,result) ->
        res.send result
        pushUpdate()
        next()


  del: (req,res,next) ->
    table.get(req.params.id).delete().run connection, (err, result) ->
      res.send 204
      pushUpdate()
      next()



class TemplateListHandler extends Handler
  db = rethinkdb.table "templates"

  get: (req,res,next) ->
    siteId = req.headers["x-bumblebee-site-id"]
#    .filter({siteId:siteId}) filter by siteit?
    db.pluck("id","name").run connection, (err,result) ->
      if err
        res.send []
      else
        result.toArray (err,results) ->
          res.send results
      next()

  put: (req,res,next) ->
    siteId = req.headers["x-bumblebee-site-id"]
    item =
      siteId: siteId
      name: "unnamed template"
      isActive: false
      fields: []
    db.insert(item).run connection, (err, result) ->
      db.get(result.generated_keys[0]).run connection, (err,result) ->
        res.send result
        #pushUpdate()
        next()


class TemplateHandler extends Handler
  table = rethinkdb.table "templates"

  get: (req,res,next) ->
    console.log req.params.id
    table.get(req.params.id).run connection, (err,result) ->
      if err
        res.send 404
      else
        res.send result
      next()


  put: (req,res,next) ->
    console.log "PUT"

    template = JSON.parse(req.body)

    table.get(template.id).replace(template).run connection, (err, result) ->
      table.get(template.id).run connection, (err,result) ->
        res.send result
        pushUpdate()
        next()


  del: (req,res,next) ->
    table.get(req.params.id).delete().run connection, (err, result) ->
      res.send 204
      pushUpdate()
      next()







class ItemListHandler extends Handler
  db = rethinkdb.table "items"

  get: (req,res,next) ->
    siteId = req.headers["x-bumblebee-site-id"]
    db.filter({siteId:siteId}).pluck("id","name").run connection, (err,result) ->
      if err
        res.send []
      else
        result.toArray (err,results) ->
          res.send results
      next()

  put: (req,res,next) ->
    siteId = req.headers["x-bumblebee-site-id"]
    item =
      siteId: siteId
      name: "new page"
      type: "page"
    db.insert(item).run connection, (err, result) ->
      db.get(result.generated_keys[0]).run connection, (err,result) ->
        res.send result
        #pushUpdate()
        next()

class BlogPostListHandler extends ItemListHandler
  db = rethinkdb.table "items"

  get: (req,res,next) ->
    siteId = req.headers["x-bumblebee-site-id"]

    filtered = db.filter
      type:"blogPost"

    if siteId # should be mandatory but useful for testing
      filtered = filtered.filter
        siteId: siteId
    if req.query.status
      filtered = filtered.filter
        status: req.query.status
    if req.query.future and req.query.future is "false"
      filtered = filtered.filter rethinkdb.row("publish_date").lt curTime()

    if req.query.view and req.query.view is "sidemenu"
      query = filtered.pluck("id","title")
    else
      query = filtered

    query.run connection, (err,result) ->
      if err
        res.send []
      else
        result.toArray (err,results) ->
          res.send results
      next()

  put: (req,res,next) ->
    siteId = req.headers["x-bumblebee-site-id"]
    item =
      siteId: siteId
      title: "new post"
      type: "blogPost"
    db.insert(item).run connection, (err, result) ->
      db.get(result.generated_keys[0]).run connection, (err,result) ->
        res.send result
        #pushUpdate()
        next()


class BlogPostHandler extends Handler
  get: (req,res,next) ->
    siteId = req.headers["x-bumblebee-site-id"]

    getBlogPost = () ->
      table = rethinkdb.table "items"
      deferred = Q.defer()
      table.get(req.params.id).run connection, (err,result) ->
        if err
          deferred.reject 404
        else
          deferred.resolve result

      deferred.promise

    getTemplate = () ->
      table = rethinkdb.table "templates"
      deferred = Q.defer()

      params =
        name: "blogpost"
        isActive: true

      table.filter(params).run connection, (err,result) ->
        result.toArray (err,results) ->
          if err
            deferred.reject 404
          else
            deferred.resolve results[0]

      deferred.promise

    getBlogPost().then (blogPost) ->
      # Upgrade the blogpost to the latest version of the schema.
      # Will need to convert to schemas at a later point
      getTemplate().then (template) ->
        for field in template.fields
          if not blogPost[field.name]
            blogPost[field.name] = ""

        console.log blogPost

        res.send
          blogPost: blogPost
          template: template
        next()

  put: (req,res,next) ->
    table = rethinkdb.table "items"
    template = JSON.parse(req.body)

    if template.publish_date
      template.publish_date *= 1

    table.get(template.id).replace(template).run connection, (err, result) ->
      console.log [err,result]
      table.get(template.id).run connection, (err,result) ->
        res.send result
        pushUpdate()
        next()


  del: (req,res,next) ->
    table = rethinkdb.table "items"
    table.get(req.params.id).delete().run connection, (err, result) ->
      res.send 204
      pushUpdate()
      next()


class ItemHandler extends Handler
  table = rethinkdb.table "items"

  get: (req,res,next) ->
    console.log req.params.id
    table.get(req.params.id).run connection, (err,result) ->
      # for section in result.sections
      #   if section.sid is undefined
      #     section.sid = section.id
      #   if section.id is undefined
      #     section.id = uuid.v1()
      if err
        res.send 404
      else
        res.send result
      next()


  put: (req,res,next) ->
    console.log "PUT"

    item = JSON.parse(req.body)

    table.get(item.id).replace(item).run connection, (err, result) ->
      table.get(item.id).run connection, (err,result) ->
        res.send result
        pushUpdate()
        next()


  del: (req,res,next) ->
    table.get(req.params.id).delete().run connection, (err, result) ->
      res.send 204
      pushUpdate()
      next()


class SettingsHandler extends Handler
  table = rethinkdb.table "sites"
  defaultSettings =
    id: "default"
    site_title: "Undefined Site"

  get: (req,res,next) ->
    siteId = req.headers["x-bumblebee-site-id"]
    table.get(siteId).run connection, (err,result) ->
      console.log [err,result]
      if result is null
        res.send defaultSettings
        next()
      else
        result["title"] = "Undefined Title" if not result["title"]
        res.send result
        next()

  put: (req,res,next) ->
    doc = JSON.parse(req.body)

    if doc.id
      table.get(doc.id).replace(doc).run connection, (err, result) ->
        table.get(doc.id).run connection, (err,result) ->
          res.send result
          pushUpdate()
          next()
    else
      # This is a new document
      table.insert(doc).run connection, (err, result) ->
        table.get(result.generated_keys[0]).run connection, (err,result) ->
          res.send result
          next()


class FileUploadHandler extends Handler
  db = rethinkdb.table "uploads"

  get: (req,res,next) ->
    console.log req.params.id
    db.get(req.params.id).run connection, (err,result) ->
      if result is null
        res.send 404
        next()
      else
        res.send result
        next()


  genDirPath =  () ->
    baseDir = "/srv/bumblebee"
    siteName = "sarahdancer.com"

    d = new Date()
    uploadDir = "uploads/" + d.getFullYear() + "/" + d.getMonth() + "/" + d.getDate()

    imgHash = uuid.v1()
    width = "original"
    height = "original"

    rel: [uploadDir,imgHash,""].join "/"
    abs: [baseDir,siteName,uploadDir,imgHash,""].join("/")


  mkdirRecursive = (path) ->
    deferred = Q.defer()
    parts = path.split("/")

    curPath = ""

    for part,i in parts
      curPath +=  part

      if i < parts.length - 1
        curPath += "/"

        exists = fs.existsSync curPath

        if fs.existsSync curPath
          isDir = fs.lstatSync(curPath).isDirectory()
        else
          fs.mkdirSync curPath

    deferred.resolve true
    deferred.promise

  saveToFile = (item, outDir) ->
    sDeferred = Q.defer()

    switch item.type
      when "image/jpeg", "image/jpg"
        imgExtension = "jpg"
      when "image/gif"
        imgExtension = "gif"
      when "image/png"
        imgExtension = "png"

    # Create a buffer to hold the Base64 encoded image
    buffer = new Buffer item.file, "base64"

    orig_size = () ->
      deferred = Q.defer()

      gm(buffer, item.name).size (err,val) ->
        if err
          deferred.reject err
        else
          deferred.resolve val

      deferred.promise

    save = (sizes) ->
      deferred = Q.defer()

      item.full_path = outDir + "original.jpg"
      item.files =
        original: sizes

      # Convert the image to a JPEG
      gm(buffer, item.name)
#        .quality(90)
        .write outDir + "original.jpg", (err) ->
          if err
            deferred.reject err
          else
            deferred.resolve item

      console.log "gm save"
      deferred.promise

    orig_size()
      .then (sizes)  ->
        save sizes
      .promise


  saveToDB = (item, outDir) ->
    deferred = Q.defer()

    doc =
      file_name: item.name
      path: outDir.rel
      sizes: [
        ["original","original"]
        [1000,1000]
        [50,50]
      ]

    console.log doc

    db.insert(doc).run connection, (err, result) ->
      db.get(result.generated_keys[0]).run connection, (err,result) ->
        deferred.resolve result

    deferred.promise

  post: (req,res,next) ->
    item = JSON.parse(req.body)

    outDir = genDirPath()
    mkdirRecursive(outDir.abs)
      .then (resq) ->
        saveToFile item, outDir.abs
      .then (resq) ->
        saveToDB item, outDir
      .done (resJSON) ->
        res.send resJSON
        next()
    , (err) ->
      console.log err
      res.send 500
      next()



    # # If converting the file has been successful then write
    # # an Upload object to the database and return it to the
    # # user.
    # # res.send {}
    # # next()

register new TemplateListHandler "/templates", ["GET","PUT"]
register new TemplateHandler "/templates/:id", ["GET","PUT"]
register new SiteListHandler "/sites", ["GET","PUT"]
register new SiteHandler "/sites/:id", ["GET","PUT"]
register new ItemListHandler "/pages", ["GET","PUT"]
register new ItemHandler "/pages/:id", ["GET","PUT","DEL"]
register new BlogPostListHandler "/blogposts", ["GET","PUT"]
register new BlogPostHandler "/blogposts/:id", ["GET","PUT","DEL"]
register new SettingsHandler "/settings", ["GET","PUT"]
register new FileUploadHandler "/file/upload", ["POST"]
register new FileUploadHandler "/file/upload/:id", ["GET"]












class WriteHandler extends Handler
  get: (req,res,next) ->
    siteId = req.headers["x-bumblebee-site-id"]
    console.log siteId
    filters =
      title: req.params.pageTitle
      siteId: siteId
    console.log filters
    table = rethinkdb.table "items"
    table.filter(filters).run connection, (err,result) ->
      if err
        res.send {}
      else
        result.toArray (err,results) ->
          if err
            res.send {}
          else
            if results.length == 0
              res.send 404
            else
              res.send results[0]
      next()

  put: (req,res,next) ->
    doc = JSON.parse(req.body)
    doc["type"] = "blogPost"
    doc["siteId"] = req.headers["x-bumblebee-site-id"]

    table = rethinkdb.table "items"

    if doc.id
      table.get(doc.id).replace(doc).run connection, (err, result) ->
        table.get(doc.id).run connection, (err,result) ->
          res.send result
          pushUpdate()
          next()
    else
      table.insert(doc).run connection, (err, result) ->
        table.get(result.generated_keys[0]).run connection, (err,result) ->
          res.send result
          next()


register new WriteHandler "/write/:pageTitle", ["GET","PUT"]

server.listen 16432

unknownMethodHandler = (req,res) ->
  if req.method.toLowerCase() is "options"
    allowHeaders = [
      "Accept"
      "Accept-Version"
      "Content-Type"
      "Origin"
      "X-Requested-With"
      "X-Bumblebee-API-Key"
      "X-Bumblebee-Site-Id"
    ]

    if res.methods.indexOf "OPTIONS" is -1
      res.methods.push "OPTIONS"


    res.header('Access-Control-Allow-Headers', allowHeaders.join(', '));
    res.header('Access-Control-Allow-Methods', res.methods.join(', '));
    res.header('Access-Control-Allow-Origin', req.headers.origin);

    res.send 204
  else
    res.send new restify.MethodNotAllowedError()
server.on 'MethodNotAllowed', unknownMethodHandler
