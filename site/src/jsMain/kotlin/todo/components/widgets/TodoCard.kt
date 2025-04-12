package todo.components.widgets

import androidx.compose.runtime.Composable
import com.varabyte.kobweb.silk.style.toAttrs
import org.jetbrains.compose.web.dom.A

@Composable
fun TodoCard(onClick: (() -> Unit)? = null, content: @Composable () -> Unit) {
    val styles = mutableListOf(TodoStyle, TodoContainerStyle, TodoTextStyle)
    if (onClick != null) {
        styles.add(TodoClickableStyle)
    }

    // Use "A" so the item supports a11y (you can tab on it and press enter to click it)
    A(href = "#", attrs = styles.toAttrs {
        tabIndex(0) // Make this item tabbable

        onClick { evt ->
            evt.preventDefault() // We are using "A" for its a11y side effects but don't want its actual behavior
            onClick?.invoke()
        }
    }) {
        content()
    }
}
