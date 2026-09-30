class ApplicationController < ActionController::API
	include Pundit::Authorization

	rescue_from Pundit::NotAuthorizedError do
		render json: { error: { code: "forbidden", message: "You are not authorized to perform this action." } }, status: :forbidden
	end

	rescue_from ActiveRecord::RecordNotFound do
		render json: { error: { code: "not_found", message: "Resource not found." } }, status: :not_found
	end
end
