//
//  Created by Zsombor Szabo on 16/08/2020.
//  Copyright © 2020 Covid Watch. All rights reserved.
//

import Foundation
import SwiftUI

extension ReportingStep2 {

    var testStart: some View {
        Group {
            Spacer(minLength: 2 * .standardSpacing)

            Text("TEST_START_DATE_QUESTION")
                .font(.custom("Montserrat-SemiBold", size: 18))
                .foregroundColor(Color("Text Color"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2 * .standardSpacing)

            Spacer(minLength: .standardSpacing)

            Button(action: {
                self.isShowingTestDatePicker.toggle()
            }) {
                TextField(NSLocalizedString("SELECT_DATE", comment: ""), text: self.$testStartDateString)
                    .padding(.horizontal, 2 * .standardSpacing)
                    .foregroundColor(Color("Text Color"))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .opacity(dontKnowTestDate ? 0.4 : 1.0)
                    .disabled(true)
            }
            .disabled(dontKnowTestDate)
            .sheet(isPresented: self.$isShowingTestDatePicker, content: {
                ZStack(alignment: .top) {
                    RKViewController(isPresented: self.$isShowingTestDatePicker, rkManager: self.testStartRKManager)
                        .padding(.top, .headerHeight)

                    HeaderBar(showMenu: false, showDismissButton: true)
                        .environmentObject(self.localStore)
                }
                .onDisappear {

                    if let selectedDate = self.testStartRKManager.selectedDate {

                        self.testStartDateString = self.dateFormatter.string(from: selectedDate)
                        self.diagnosis.testDate = selectedDate

                    } else {
                        self.testStartRKManager.selectedDate = self.diagnosis.testDate
                    }
                }
            })

            Spacer(minLength: .standardSpacing)

            HStack(alignment: .center) {

                Button(action: {
                    withAnimation {
                        self.dontKnowTestDate.toggle()
                        if self.dontKnowTestDate {
                            self.testStartRKManager.selectedDate = nil
                            self.testStartDateString = ""
                            self.diagnosis.testDate = nil
                        }
                    }
                }) {
                    if self.dontKnowTestDate {
                        Image("Checkbox Checked")
                    } else {
                        Image("Checkbox Unchecked")
                    }

                    Text("TEST_START_DATE_UNKNOWN")
                        .foregroundColor(Color("Text Color"))
                }
            }.padding(.horizontal, 2 * .standardSpacing)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            Spacer().frame(height: 2 * .standardSpacing)

        }
    }

    public func configureTestStartDisabledDates() {
        testStartRKManager.minimumDate = exposedStartRKManager.selectedDate ?? Date()
    }
}
