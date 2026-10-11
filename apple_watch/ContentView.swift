import SwiftUI

struct ContentView: View {
    @EnvironmentObject var connector: WatchConnector
    @GestureState private var pressing = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(pressing ? Color.red.opacity(0.6) : Color.red)
                    .frame(width: 100, height: 100)
                Text("SOS")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
            }
            // Hold for 1.5 s: deliberate action, avoids accidental alerts.
            .gesture(
                LongPressGesture(minimumDuration: 1.5)
                    .updating($pressing) { current, state, _ in state = current }
                    .onEnded { _ in connector.sendSOS() }
            )
            Text(connector.status)
                .font(.footnote)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
