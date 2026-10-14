import SwiftUI

struct TimeSheet: View {
    @Environment(SearchModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = Date.now
    @State private var isDeparture = true

    var body: some View {
        NavigationStack {
            Form {
                Picker("Typ", selection: $isDeparture) {
                    Text("Odjezd").tag(true)
                    Text("Příjezd").tag(false)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                Section {
                    DatePicker("Datum a čas", selection: $draft, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.graphical)
                }

                Section {
                    HStack {
                        quick("Teď") { draft = .now }
                        quick("+15 min") { draft = draft.addingTimeInterval(15 * 60) }
                        quick("+1 h") { draft = draft.addingTimeInterval(3600) }
                        quick("Zítra 7:00") { draft = tomorrow(hour: 7) }
                    }
                    .buttonStyle(.bordered)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("Čas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Teď", systemImage: "arrow.counterclockwise") {
                        model.date = nil
                        model.isDeparture = true
                        finish()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hotovo", systemImage: "checkmark") {
                        model.date = abs(draft.timeIntervalSinceNow) < 60 ? nil : draft
                        model.isDeparture = isDeparture
                        finish()
                    }
                }
            }
            .onAppear {
                draft = model.date ?? .now
                isDeparture = model.isDeparture
            }
        }
    }

    private func finish() {
        if model.canSearch { model.search() }
        dismiss()
    }

    private func quick(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.footnote)
            .frame(maxWidth: .infinity)
    }

    private func tomorrow(hour: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = RPCDate.prague
        let day = cal.date(byAdding: .day, value: 1, to: .now)!
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }
}

struct OptionsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section("Dopravní prostředky") {
                    ForEach(VehicleType.selectable, id: \.self) { vehicle in
                        Toggle(isOn: binding(for: vehicle)) {
                            Label {
                                Text(vehicle.name)
                            } icon: {
                                Image(systemName: vehicle.symbol)
                                    .foregroundStyle(vehicle.baseColor)
                            }
                        }
                    }
                }

                Section("Přestupy") {
                    Picker("Maximální počet", selection: $store.searchOptions.maxTransfers) {
                        Text("Bez omezení").tag(Int?.none)
                        Text("Pouze přímé").tag(Int?.some(0))
                        Text("Nejvýše 1").tag(Int?.some(1))
                        Text("Nejvýše 2").tag(Int?.some(2))
                        Text("Nejvýše 3").tag(Int?.some(3))
                    }
                }

                Section("Pohodlí") {
                    Toggle(isOn: $store.searchOptions.lowFloor) {
                        Label("Bezbariérově", systemImage: "figure.roll")
                    }
                    Toggle(isOn: $store.searchOptions.stroller) {
                        Label("S kočárkem", systemImage: "stroller.fill")
                    }
                    Toggle(isOn: $store.searchOptions.bike) {
                        Label("S kolem", systemImage: "bicycle")
                    }
                    Toggle(isOn: $store.searchOptions.airCondition) {
                        Label("Klimatizace", systemImage: "snowflake")
                    }
                }

                if !store.searchOptions.isDefault {
                    Section {
                        Button("Obnovit výchozí", role: .destructive) {
                            store.searchOptions = SearchOptions()
                        }
                    }
                }
            }
            .navigationTitle("Možnosti hledání")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hotovo", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }

    private func binding(for vehicle: VehicleType) -> Binding<Bool> {
        Binding {
            store.searchOptions.vehicles.contains(vehicle)
        } set: { on in
            if on {
                store.searchOptions.vehicles.insert(vehicle)
            } else if store.searchOptions.vehicles.count > 1 {
                store.searchOptions.vehicles.remove(vehicle)
            }
        }
    }
}
