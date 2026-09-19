import Foundation

/// The data the iOS client exchanges with the 2048 Cloud API.
///
/// Plain value types with hand-written coding, no framework and no generated
/// code, so the whole cloud layer is testable without a simulator. See
/// `docs/backend.md` for the wire contract they mirror.

/// A round, in the shape the API stores it: flat cells, row-major.
struct CloudSave: Codable, Equatable {
    var board: [Int]
    var score: Int
    var bestScore: Int
    var won: Bool
    var gameOver: Bool
    var moves: Int
    var elapsedSeconds: Int
    /// The revision this device last saw, proving a save is a continuation.
    var baseRevision: Int?
    var revision: Int

    init(
        board: [Int],
        score: Int,
        bestScore: Int,
        won: Bool,
        gameOver: Bool,
        moves: Int,
        elapsedSeconds: Int = 0,
        baseRevision: Int? = nil,
        revision: Int = 0
    ) {
        self.board = board
        self.score = score
        self.bestScore = bestScore
        self.won = won
        self.gameOver = gameOver
        self.moves = moves
        self.elapsedSeconds = elapsedSeconds
        self.baseRevision = baseRevision
        self.revision = revision
    }

    /// Defaults everywhere, because a field the server adds later must not
    /// break a build that predates it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        board = try container.decodeIfPresent([Int].self, forKey: .board) ?? []
        score = try container.decodeIfPresent(Int.self, forKey: .score) ?? 0
        bestScore = try container.decodeIfPresent(Int.self, forKey: .bestScore) ?? 0
        won = try container.decodeIfPresent(Bool.self, forKey: .won) ?? false
        gameOver = try container.decodeIfPresent(Bool.self, forKey: .gameOver) ?? false
        moves = try container.decodeIfPresent(Int.self, forKey: .moves) ?? 0
        elapsedSeconds = try container.decodeIfPresent(Int.self, forKey: .elapsedSeconds) ?? 0
        baseRevision = try container.decodeIfPresent(Int.self, forKey: .baseRevision)
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
    }

    /// The 4×4 form the SwiftUI board iterates.
    var grid: [[Int]] {
        stride(from: 0, to: board.count, by: 4).map { Array(board[$0..<min($0 + 4, board.count)]) }
    }
}

struct CloudStatistics: Codable, Equatable {
    var bestScore: Int = 0
    var gamesPlayed: Int = 0
    var gamesWon: Int = 0
    var highestTile: Int = 0

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bestScore = try container.decodeIfPresent(Int.self, forKey: .bestScore) ?? 0
        gamesPlayed = try container.decodeIfPresent(Int.self, forKey: .gamesPlayed) ?? 0
        gamesWon = try container.decodeIfPresent(Int.self, forKey: .gamesWon) ?? 0
        highestTile = try container.decodeIfPresent(Int.self, forKey: .highestTile) ?? 0
    }

    init(bestScore: Int = 0, gamesPlayed: Int = 0, gamesWon: Int = 0, highestTile: Int = 0) {
        self.bestScore = bestScore
        self.gamesPlayed = gamesPlayed
        self.gamesWon = gamesWon
        self.highestTile = highestTile
    }
}

struct CloudUser: Codable, Equatable, Identifiable {
    var id: String = ""
    var username: String = ""
    var displayName: String = ""
    var email: String = ""
    var statistics = CloudStatistics()

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        let name = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        // A player with no display name is shown by username rather than by a
        // blank row.
        displayName = name.isEmpty ? username : name
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        statistics = try container.decodeIfPresent(CloudStatistics.self, forKey: .statistics) ?? CloudStatistics()
    }

    init(id: String = "", username: String = "", displayName: String = "", email: String = "", statistics: CloudStatistics = CloudStatistics()) {
        self.id = id
        self.username = username
        self.displayName = displayName.isEmpty ? username : displayName
        self.email = email
        self.statistics = statistics
    }
}

struct CloudTokens: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
}

struct CloudSession: Equatable {
    var user: CloudUser
    var tokens: CloudTokens
}

/// How a sync was resolved.
///
/// `conflicted` is not an error: the further round won and the other was
/// preserved in a recoverable slot, which is the whole reason the API refuses
/// to do last-writer-wins.
enum SyncResolution: String, Codable {
    case uploaded, downloaded, conflicted
    case inSync = "in_sync"

    init(rawValue raw: String) {
        switch raw {
        case "uploaded": self = .uploaded
        case "downloaded": self = .downloaded
        case "conflicted": self = .conflicted
        // A server that grows a new resolution must not break an old build.
        default: self = .inSync
        }
    }
}

struct SyncResult {
    var resolution: SyncResolution
    var save: CloudSave?
    var conflictSlot: String?
    var winner: String?
}

struct LeaderboardEntry: Identifiable, Equatable {
    var rank: Int
    var username: String
    var displayName: String
    var score: Int
    var highestTile: Int
    var isViewer: Bool

    var id: String { "\(rank)-\(username)" }
}

struct LeaderboardPage: Equatable {
    var entries: [LeaderboardEntry]
    var players: Int
    var topScore: Int
}

/// A failure a caller can show to a player.
///
/// `code` is the server's stable identifier, or `network` when the request
/// never got that far. Branch on the code; the message is for the screen.
struct CloudError: Error, Equatable {
    let code: String
    let message: String
    let status: Int

    init(code: String, message: String, status: Int = 0) {
        self.code = code
        self.message = message
        self.status = status
    }

    var isUnauthorized: Bool { status == 401 }
    var isNetworkFailure: Bool { code == "network" }

    static let unauthorized = CloudError(code: "unauthorized", message: "Sign in to use this.", status: 401)
    static let network = CloudError(
        code: "network",
        message: "Could not reach the 2048 cloud. Your game is still saved on this device."
    )
}
