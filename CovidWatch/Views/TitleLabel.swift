//
//  Created by Zsombor Szabo on 03/05/2020.
//  
//

import SwiftUI

struct TitleLabel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.custom("Montserrat-SemiBold", size: 33))
            .foregroundColor(Color("titleLabel"))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2 * .standardSpacing)
    }
}
