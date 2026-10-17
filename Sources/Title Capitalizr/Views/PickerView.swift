//
//  PickerView.swift
//  Title Capitalizr
//
//  Created by John Seong on 2022-05-16.
//

import SwiftUI

struct PickerView: View {
    @Binding var selectedOutput: DesiredOutput
    
    @Environment(\.dismiss) private var dismiss

    var btnBack: some View {
        Button(action: { dismiss() }) {
            HStack {
                Image(systemName: "chevron.backward")
                    .aspectRatio(contentMode: .fit)
                Text("Back")
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                Picker("Style", selection: $selectedOutput) {
                    ForEach(DesiredOutput.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                #if os(macOS)
                .pickerStyle(.inline)
                #endif
            }
            .navigationTitle("Customize")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { btnBack }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 260)
        #endif
        
        Text("Developed and Designed by John Seong")
            .padding(.bottom)
    }
}
