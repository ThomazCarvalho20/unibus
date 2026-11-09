routerAdd("POST", "/api/unibus/register", (e) => {
  const service = require(__hooks + "/service.js")
  return e.json(201, service.register(e.app, e.requestInfo().body))
})

routerAdd("GET", "/api/unibus/dashboard", (e) => {
  const service = require(__hooks + "/service.js")
  return e.json(200, service.dashboard(e.app, e.auth.id))
}, $apis.requireAuth("users"))

routerAdd("POST", "/api/unibus/action/{name}", (e) => {
  const service = require(__hooks + "/service.js")
  const name = e.request.pathValue("name")
  const body = e.requestInfo().body
  e.app.runInTransaction((app) => service.action(app, e.auth.id, name, body))
  return e.json(200, { success: true })
}, $apis.requireAuth("users"))
