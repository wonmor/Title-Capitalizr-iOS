//
//  PickerView.swift
//  Title Capitalizr
//
//  Created by John Seong on 2022-05-16.
//

import SwiftUI

struct PickerView: View {
    @Binding var selectedOutput: DesiredOutput
    
    var body: some View {
        NavigationView {
            List {
                Picker("STYLE", selection: $selectedOutput) {
                    Text("MLA").tag(DesiredOutput.mla)
                    Text("APA").tag(DesiredOutput.apa)
                    Text("CHICAGO").tag(DesiredOutput.chicago)
                }
            }
            .navigationBarTitle("Customize")
        }
    }
}

struct PickerView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
