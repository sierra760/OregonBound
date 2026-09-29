import SwiftUI
import OSLog

private let menuLogger = Logger(subsystem: "com.sierraburkhart.OregonBound", category: "MainMenu")

// Profession names in ditl_9022 / STR# 3005 order. Values 1–8 map to array index + 1.
private let professionNames = [
    "Banker", "Blacksmith", "Carpenter", "Doctor",
    "Farmer", "Merchant", "Saddlemaker", "Teacher"
]

// Difficulty levels from STR# 3004. Values 1–3 map to array index + 1.
private let difficultyNames = ["Greenhorn", "Adventurer", "Trail Guide"]

struct MainMenuView: View {
    @State private var selectedProfession = 1
    @State private var selectedDifficulty = 1
    @State private var showGame = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Oregon Bound")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top, 48)

            Spacer()

            Form {
                Section("Choose Your Profession") {
                    Picker("Profession", selection: $selectedProfession) {
                        ForEach(1...8, id: \.self) { value in
                            Text(professionNames[value - 1]).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Choose Difficulty") {
                    Picker("Difficulty", selection: $selectedDifficulty) {
                        ForEach(1...3, id: \.self) { value in
                            Text(difficultyNames[value - 1]).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .frame(maxHeight: 220)

            Spacer()

            Button(action: startGame) {
                Text("Play")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .frame(minWidth: 160)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 48)
        }
        .navigationTitle("Oregon Bound")
        .navigationDestination(isPresented: $showGame) {
            GameSceneContainerView(profession: selectedProfession, difficulty: selectedDifficulty)
                .ignoresSafeArea()
                .navigationBarBackButtonHidden(true)
        }
    }

    private func startGame() {
        menuLogger.info(
            "MainMenu: Play tapped — profession=\(selectedProfession, privacy: .public) (\(professionNames[selectedProfession - 1], privacy: .public)) difficulty=\(selectedDifficulty, privacy: .public) (\(difficultyNames[selectedDifficulty - 1], privacy: .public))"
        )
        showGame = true
    }
}
