migrate((app) => {
  const text = (name, max = 120) => new TextField({ name, required: true, max })
  const ref = (name, collection) => new RelationField({
    name, collectionId: collection.id, required: true, maxSelect: 1,
  })
  const choice = (name, values) => new SelectField({ name, values, required: true, maxSelect: 1 })
  const collection = (name, fields, indexes = []) => {
    const schema = new Collection({ name, type: "base" })
    fields.forEach((field) => schema.fields.add(field))
    schema.indexes = indexes
    app.save(schema)
    return schema
  }

  const users = app.findCollectionByNameOrId("users")
  users.createRule = null
  users.updateRule = null
  users.fields.add(text("nametag", 24))
  users.indexes = [...users.indexes, "CREATE UNIQUE INDEX idx_users_nametag ON users (nametag)"]
  app.save(users)

  const companies = collection("companies", [text("name")])
  collection("memberships", [
    ref("company", companies), ref("user", users),
    choice("role", ["admin", "driver", "representative", "student"]),
    choice("status", ["pending", "active", "suspended"]),
  ], ["CREATE UNIQUE INDEX idx_memberships_company_user ON memberships (company, user)"])
  const routes = collection("routes", [
    ref("company", companies), text("name"), text("stops", 2000),
  ])
  const vehicles = collection("vehicles", [
    ref("company", companies), text("name"), text("plate", 10),
    new NumberField({ name: "capacity", required: true, min: 1, max: 200, onlyInt: true }),
  ], ["CREATE UNIQUE INDEX idx_vehicles_plate ON vehicles (company, plate)"])
  collection("assignments", [
    ref("route", routes), ref("student", users),
  ], ["CREATE UNIQUE INDEX idx_assignments_student_route ON assignments (student, route)"])
  const trips = collection("trips", [
    ref("route", routes), ref("vehicle", vehicles), ref("driver", users),
    choice("direction", ["outbound", "return"]),
    new DateField({ name: "departure", required: true }),
    choice("status", ["scheduled", "active", "finished", "cancelled"]),
  ])
  collection("attendance", [
    ref("trip", trips), ref("student", users),
    choice("status", ["confirmed", "absent"]),
    new AutodateField({ name: "updated", onCreate: true, onUpdate: true }),
  ], ["CREATE UNIQUE INDEX idx_attendance_student_trip ON attendance (student, trip)"])
  collection("boardings", [
    ref("trip", trips), ref("student", users), ref("actor", users),
    new AutodateField({ name: "created", onCreate: true }),
  ], ["CREATE UNIQUE INDEX idx_boardings_student_trip ON boardings (student, trip)"])
})
