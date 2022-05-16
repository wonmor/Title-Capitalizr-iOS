//
//  ContentView.swift
//  Title Capitalizr
//
//  Created by John Seong on 2022-05-16.
//

import SwiftUI

struct ContentView: View {
    @State private var titleName: String = ""
    @State private var showingSheet = false
    @State private var selectedOutput: DesiredOutput = .mla
    
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
                    Text("Press here to select style")
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
        }.padding()
    }
    
    private func resultSection() -> some View {
        VStack {
            Text(titleName == "" ? "This is where your capitalized title will appear..." : titleName)
                .textSelection(.enabled)
            
            Button(action: { pasteboard.string = titleName }) {
                HStack {
                    Image(systemName: "doc.on.doc.fill")
                    Text("Copy to clipboard")
                        .font(.body)
                }
                .padding(8)
                .foregroundColor(.black)
                .contentShape(Rectangle())
                .overlay(
                    RoundedRectangle(cornerRadius: 10.0)
                        .stroke(lineWidth: 2.0)
                        .foregroundColor(.black)
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
