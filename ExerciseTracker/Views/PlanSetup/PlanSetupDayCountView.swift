import SwiftUI

struct PlanSetupDayCountView: View {
    @Environment(AppState.self) private var appState
    @State private var dayCount = 4
    
    var body: some View {
        ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 16) {
                        Image("WorkoutMascot")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 88, height: 88)
                        
                        Text("Create Your Workout Plan")
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.8)
                        
                        Text("How many days per week is your workout plan?")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)
                    
                    VStack(spacing: 12) {
                        Stepper(value: $dayCount, in: 1...7) {
                            HStack {
                                Text("Workout Days")
                                    .font(.headline)
                                Spacer()
                                Text("\(dayCount)")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .monospacedDigit()
                            }
                            .contentShape(Rectangle())
                        }
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        
                        Text("You'll configure exercises for each of the \(dayCount) day\(dayCount == 1 ? "" : "s") next.")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)
                    
                    Button {
                        appState.navigationPath.append(PlanSetupStep.dayConfig(dayIndex: 1, totalDays: dayCount))
                    } label: {
                        Text("Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 8)
                }
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Setup")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
        }
}
