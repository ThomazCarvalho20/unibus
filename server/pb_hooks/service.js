function list(app, collection, filter, params) {
  return app.findRecordsByFilter(collection, filter, "", 0, 0, params)
}

function first(app, collection, filter, params) {
  return list(app, collection, filter, params)[0]
}

function save(app, collection, data, record) {
  const target = record || new Record(app.findCollectionByNameOrId(collection))
  Object.keys(data).forEach((key) => target.set(key, data[key]))
  app.save(target)
  return target
}

function member(app, company, user) {
  return first(app, "memberships", "company = {:company} && user = {:user}", { company, user })
}

function activeRole(app, company, user) {
  const membership = member(app, company, user)
  return membership && membership.getString("status") === "active"
    ? membership.getString("role") : ""
}

function requireRole(app, company, user, roles) {
  if (!roles.includes(activeRole(app, company, user))) {
    throw new ForbiddenError("Você não tem acesso a esta operação.")
  }
}

function isAssigned(app, route, student) {
  return !!first(app, "assignments", "route = {:route} && student = {:student}", { route, student })
}

function read(app, collection, id) {
  const result = first(app, collection, "id = {:id}", { id })
  if (!result) throw new NotFoundError("Registro não encontrado.")
  return result
}

function fields(record, names) {
  const result = { id: record.id }
  names.split(" ").forEach((name) => { result[name] = record.get(name) })
  return result
}

function profile(record) {
  return fields(record, "name nametag")
}

function register(app, data) {
  const name = String(data.name || "").trim()
  const email = String(data.email || "").trim().toLowerCase()
  const password = String(data.password || "")
  if (!name || name.length > 120 || !email || password.length < 10 || password.length > 72) {
    throw new BadRequestError("Informe seu nome, e-mail e uma senha de 10 a 72 caracteres.")
  }
  return profile(save(app, "users", { name, email, password, nametag: $security.randomString(12).toUpperCase() }))
}

function dashboard(app, user) {
  const companies = list(app, "memberships", "user = {:user} && status != 'suspended'", { user })
    .map((membership) => {
      const company = membership.getString("company")
      const role = membership.getString("role")
      const status = membership.getString("status")
      const data = { ...fields(read(app, "companies", company), "name"), role, status }
      if (status !== "active") return data
      const admin = role === "admin"
      const student = role === "student"
      data.routes = list(app, "routes", "company = {:company}", { company })
        .filter((route) => !student || isAssigned(app, route.id, user))
        .map((route) => {
          const trips = list(app, "trips", "route = {:route}", { route: route.id })
            .filter((trip) => role !== "driver" || trip.getString("driver") === user)
            .map((trip) => {
              const vehicle = read(app, "vehicles", trip.getString("vehicle"))
              const tripData = {
                ...fields(trip, "direction departure status"),
                vehicle: vehicle.getString("name"),
                plate: vehicle.getString("plate"),
                capacity: vehicle.getInt("capacity"),
                driver: read(app, "users", trip.getString("driver")).getString("name"),
              }
              const assignmentFilter = student ? "route = {:route} && student = {:user}" : "route = {:route}"
              tripData.passengers = list(app, "assignments", assignmentFilter, { route: route.id, user })
                .map((assignment) => assignment.getString("student"))
                .filter((id) => activeRole(app, company, id) === "student")
                .map((id) => {
                  const attendance = first(app, "attendance", "trip = {:trip} && student = {:id}", { trip: trip.id, id })
                  const boarding = first(app, "boardings", "trip = {:trip} && student = {:id}", { trip: trip.id, id })
                  return {
                    ...profile(read(app, "users", id)),
                    attendance: attendance ? attendance.getString("status") : "pending",
                    boarding: boarding ? {
                      time: boarding.getString("created"),
                      actor: read(app, "users", boarding.getString("actor")).getString("name"),
                    } : null,
                  }
                })
              return tripData
            })
          return { ...fields(route, "name stops"), trips }
        }).filter((route) => role !== "driver" || route.trips.length > 0)
      if (admin) {
        data.vehicles = list(app, "vehicles", "company = {:company}", { company })
          .map((vehicle) => fields(vehicle, "name plate capacity"))
        data.members = list(app, "memberships", "company = {:company}", { company })
          .map((m) => ({
            ...profile(read(app, "users", m.getString("user"))),
            role: m.getString("role"), status: m.getString("status"),
          }))
      }
      return data
    })
  return { user: profile(read(app, "users", user)), companies }
}

function action(app, user, name, data) {
  const company = String(data.company || "")
  if (name === "accept") {
    const membership = member(app, company, user)
    if (!membership || membership.getString("status") !== "pending") {
      throw new BadRequestError("Convite pendente não encontrado.")
    }
    save(app, "memberships", { status: "active" }, membership)
    return
  }
  if (name === "attendance" || name === "boarding" || name === "trip_status") {
    operateTrip(app, user, name, data)
    return
  }

  requireRole(app, company, user, ["admin"])
  switch (name) {
    case "invite": {
      const nametag = String(data.nametag || "").trim().toUpperCase()
      const target = first(app, "users", "nametag = {:nametag}", { nametag })
      if (!target) throw new NotFoundError("Nametag não encontrado.")
      if (member(app, company, target.id)) throw new BadRequestError("Esta conta já tem um vínculo com a empresa.")
      if (!["student", "driver", "representative"].includes(data.role)) throw new BadRequestError("Perfil inválido.")
      save(app, "memberships", { company, user: target.id, role: data.role, status: "pending" })
      return
    }
    case "suspend": {
      const membership = member(app, company, data.user)
      if (!membership || membership.getString("role") === "admin") throw new BadRequestError("Vínculo inválido.")
      save(app, "memberships", { status: "suspended" }, membership)
      return
    }
    case "route":
      save(app, "routes", { company, name: data.name, stops: data.stops })
      return
    case "vehicle":
      save(app, "vehicles", { company, name: data.name, plate: String(data.plate || "").trim().toUpperCase(), capacity: data.capacity })
      return
    case "assign": {
      const route = read(app, "routes", data.route)
      if (route.getString("company") !== company || activeRole(app, company, data.student) !== "student") {
        throw new BadRequestError("Rota ou estudante inválido.")
      }
      if (!isAssigned(app, route.id, data.student)) {
        save(app, "assignments", { route: route.id, student: data.student })
      }
      return
    }
    case "trip": {
      const route = read(app, "routes", data.route)
      const vehicle = read(app, "vehicles", data.vehicle)
      if (route.getString("company") !== company || vehicle.getString("company") !== company ||
          activeRole(app, company, data.driver) !== "driver") {
        throw new BadRequestError("Rota, veículo ou motorista inválido.")
      }
      save(app, "trips", {
        route: route.id, vehicle: vehicle.id, driver: data.driver,
        direction: data.direction, departure: data.departure, status: "scheduled",
      })
      return
    }
    default:
      throw new NotFoundError("Operação desconhecida.")
  }
}

function operateTrip(app, user, name, data) {
  const trip = read(app, "trips", data.trip)
  const route = read(app, "routes", trip.getString("route"))
  const company = route.getString("company")
  const role = activeRole(app, company, user)
  const status = trip.getString("status")
  const driver = role === "driver" && trip.getString("driver") === user
  if (name === "trip_status") {
    if (role !== "admin" && !driver) throw new ForbiddenError("Viagem não autorizada.")
    const allowed = { scheduled: ["active", "cancelled"], active: ["finished", "cancelled"] }
    if (!(allowed[status] || []).includes(data.status)) throw new BadRequestError("Alteração de status inválida.")
    save(app, "trips", { status: data.status }, trip)
    return
  }

  const student = role === "student" ? user : data.student
  if (!student || activeRole(app, company, student) !== "student" || !isAssigned(app, route.id, student)) {
    throw new ForbiddenError("Passageiro não autorizado para esta viagem.")
  }
  const filter = "trip = {:trip} && student = {:student}"
  const key = { trip: trip.id, student }
  if (name === "attendance") {
    if (role !== "student") throw new ForbiddenError("A confirmação é feita pelo estudante.")
    if (status !== "scheduled") throw new BadRequestError("Esta viagem não aceita mais confirmações.")
    save(app, "attendance", { ...key, status: data.status }, first(app, "attendance", filter, key))
    return
  }

  if (!["student", "admin", "representative"].includes(role) && !driver) {
    throw new ForbiddenError("Você não pode registrar embarques nesta viagem.")
  }
  if (first(app, "boardings", filter, key)) return
  if (status !== "active") throw new BadRequestError("O embarque só pode ser registrado durante a viagem.")
  save(app, "boardings", { ...key, actor: user })
}

module.exports = { action, dashboard, register }
