import Testing
@testable import ShellUI

@Suite struct LibraryFilterTests {
    private func game(_ id: String, _ state: GameState) -> GameDetail { GameDetail(game: GameTile(id: id, title: id, state: state)) }

    @Test func gamesThatNeedTheirDataAreLeftOutWhenTheSettingIsOn() {
        let games = [game("a", .playable), game("b", .needsGameData), game("c", .needsAppUpdate), game("d", .broken(reason: "x"))]
        #expect(LibraryFilter.visible(games, hideWithoutData: true).map(\.id) == ["a", "c", "d"], "only a missing game data hides a game")
        #expect(LibraryFilter.visible(games, hideWithoutData: false).map(\.id) == ["a", "b", "c", "d"])
    }

    @Test func aLibraryWhoseGamesAllNeedTheirDataShowsThemAll() {
        let waiting = [game("a", .needsGameData), game("b", .needsGameData)]
        #expect(LibraryFilter.visible(waiting, hideWithoutData: true).map(\.id) == ["a", "b"])
        #expect(LibraryFilter.visible([], hideWithoutData: true).isEmpty)
    }
}
