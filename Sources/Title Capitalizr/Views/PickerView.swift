//
//  PickerView.swift
//  Title Capitalizr
//
//  Created by John Seong on 2022-05-16.
//

import SwiftUI

struct PickerView: View {
    @Binding var selectedOutput: DesiredOutput
    
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

        var btnBack : some View { Button(action: {
            self.presentationMode.wrappedValue.dismiss()
            }) {
                HStack {
                Image(systemName: "chevron.backward") // set image here
                    .aspectRatio(contentMode: .fit)
                    Text("Back")
                }
            }
        }
    
    var body: some View {
        NavigationView {
            List {
                Picker("Style", selection: $selectedOutput) {
                    Text("MLA and Chicago").tag(DesiredOutput.mla)
                    Text("APA and AP").tag(DesiredOutput.apa)
                }
            }
            .navigationBarTitle("Customize")
            .navigationBarItems(leading: btnBack)
        }
        Text("Developed and Designed by John Seong")
    }
}
