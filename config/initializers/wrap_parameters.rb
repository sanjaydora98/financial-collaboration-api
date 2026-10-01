# This API-only app is pure JSON: every client request already nests its
# payload under an explicit top-level key (e.g. {"expense": {...}}), and every
# controller reads that key directly via `params.fetch(:expense, ...)` etc.
# Rails' automatic ParamsWrapper middleware is therefore unnecessary here, and
# it was actively harmful: because the frontend sends `Content-Type:
# application/json` even on bodyless GET requests, the wrapper injected an
# empty hash under a key derived from the controller name (e.g.
# `{"authentication"=>{}}` for AuthenticationController, which has no backing
# model) into every request's params, producing "Unpermitted parameter"
# warnings and corrupting GET params. Disabling wrapping removes this
# unnecessary strong-parameter path without changing the API contract, since
# no controller or client relies on the wrapped keys.
ActiveSupport.on_load(:action_controller) do
  wrap_parameters format: []
end
