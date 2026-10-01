frontend_origin = ENV.fetch("FRONTEND_ORIGIN", "http://localhost:3001")

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins frontend_origin

    resource "*",
      headers: :any,
      methods: %i[get post put patch delete options head],
      max_age: 600
  end
end
