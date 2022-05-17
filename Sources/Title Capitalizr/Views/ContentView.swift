//
//  ContentView.swift
//  Title Capitalizr
//
//  Created by John Seong on 2022-05-16.
//

import SwiftUI

let desiredOutputDict = [DesiredOutput.mla: "MLA",
                         DesiredOutput.apa: "APA",
                         DesiredOutput.chicago: "Chicago"]

struct ContentView: View {
    @State private var titleName: String = ""
    @State private var textOutput: String = ""
    @State private var showingSheet = false
    @State private var selectedOutput: DesiredOutput = .mla
    
    // Detect whether OS is on dark mode or light mode
    @Environment(\.colorScheme) var colorScheme
    
    let pasteboard = UIPasteboard.general
    
    var body: some View {
        VStack(alignment: .center) {
            titleBar()
            textEntry()
            resultSection()
        }
    }
    
    private func titleBar() -> some View {
        VStack(spacing: -20) {
            Text("Title Capitalzr")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding()
            
            Button(action: { showingSheet.toggle() }) {
                VStack {
                    Text("Press here to select **style**")
                        .font(.title2)
                        .padding()
                }
            }
            .sheet(isPresented: $showingSheet) {
                PickerView(selectedOutput: $selectedOutput)
            }
        }
    }
    
    private func textEntry() -> some View {
        VStack(alignment: .center) {
            Text("Are you going to be the next Tolkien?")
                .font(.callout)
                .bold()
            TextField("Enter your title name...", text: $titleName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            Text("Selected: **\(desiredOutputDict[selectedOutput]!)**")
                .textSelection(.enabled)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    private func resultSection() -> some View {
        VStack {
            Text(self.titleName.trimmingCharacters(in: .whitespacesAndNewlines) == "" ? "Your capitalized title will appear here..." : Capitalizer(inputLine: self.titleName).capitalizeTitle(selectedOutput: self.selectedOutput))
                .textSelection(.enabled)
                .padding(.leading)
                .padding(.trailing)
                .padding(.top)
                .multilineTextAlignment(.center)
            
            Button(action: { pasteboard.string = self.titleName }) {
                HStack {
                    Image(systemName: "doc.on.doc.fill")
                    Text("Copy to **clipboard**")
                        .font(.body)
                }
                .padding(8)
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .contentShape(Rectangle())
                .overlay(
                    RoundedRectangle(cornerRadius: 10.0)
                        .stroke(lineWidth: 2.0)
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                )
            }
        }
        
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
