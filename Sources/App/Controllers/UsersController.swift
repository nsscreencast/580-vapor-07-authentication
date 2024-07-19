import Vapor
import Fluent

struct UserBasicAuthenticator: AsyncBasicAuthenticator {
    func authenticate(basic: BasicAuthorization, for request: Request) async throws {
        guard let user = try await User.query(on: request.db)
            .filter(\.$email, .custom("ILIKE"), basic.username)
            .first()
        else {
            return
        }

        guard try Bcrypt.verify(basic.password, created: user.passwordHash) else {
            return
        }

        request.auth.login(user)
    }
}

struct UserAuthTokenAuthenticator: AsyncBearerAuthenticator {
    func authenticate(bearer: BearerAuthorization, for request: Request) async throws {
        // pretend we had some other auth here...
    }
}

struct UsersController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let users = routes.grouped("users")

        users.post(use: create)

        let protected = users
            .grouped(UserBasicAuthenticator())
            .grouped(UserAuthTokenAuthenticator())
            .grouped(User.guardMiddleware())

        protected.get("me", use: show)
    }

    @Sendable
    func create(_ req: Request) async throws -> User.Response {
        try User.CreatePayload.validate(content: req)

        let payload = try req.content.decode(User.CreatePayload.self)
        guard payload.password == payload.passwordConfirmation else {
            throw Abort(.badRequest, reason: "Passwords did not match")
        }

        let user = try User(
            email: payload.email,
            passwordHash: Bcrypt.hash(payload.password)
        )
        try await user.save(on: req.db)

        return try user.response
    }

    @Sendable
    func show(_ req: Request) async throws -> User.Response {
        let user = try req.auth.require(User.self)
        return try user.response
    }
}

