package jp.espresso3389.pdfrx_example

import androidx.test.rule.ActivityTestRule
import dev.flutter.plugins.integration_test.FlutterTestRunner
import org.junit.Rule
import org.junit.runner.RunWith

@RunWith(FlutterTestRunner::class)
class MainActivityTest {
    @JvmField
    @Rule
    val rule = ActivityTestRule(MainActivity::class.java, true, false)
}
