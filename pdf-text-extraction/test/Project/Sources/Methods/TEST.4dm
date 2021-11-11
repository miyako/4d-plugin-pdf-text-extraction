//%attributes = {}
$path:=Folder:C1567(fk resources folder:K87:11).file("test.pdf").platformPath

$status:=PDF Extract text ($path)

If ($status.success)
	
	$lines:=Split string:C1554($status.text;"\r\n")
	
End if 