#!/usr/bin/ruby 

$:.unshift  "../lib/" if File.directory?("../lib")

require 'test/unit'
require 'symbiosis/domain/ssl'
require 'symbiosis/test/domain'

class SSLTest < Test::Unit::TestCase

  @@serial=0

  def setup
    @domain = Symbiosis::Domain.new()
    @domain.create
  end

  def teardown
    @domain.destroy unless $DEBUG
  end

  #####
  #
  # Helper methods
  #
  #####

  #
  # Returns a private key
  #
  def do_generate_key
    # This is a very short key!
    OpenSSL::PKey::RSA.new(512)
  end

  #
  # Returns a new certificate given a key
  #
  def do_generate_crt(domain, key=nil, ca_cert=nil, ca_key=nil)
    #
    # Generate a key if none has been specified
    #
    key = do_generate_key if key.nil?

    #
    # Check CA key and cert
    #
    if !ca_cert.nil? and !ca_key.nil? and !ca_cert.check_private_key(ca_key)
      warn "CA certificate and key do not match -- not using." 
      ca_cert = ca_key = nil
    end

    # Generate the request 
    csr            = OpenSSL::X509::Request.new
    csr.version    = 0
    csr.subject    = OpenSSL::X509::Name.new( [ ["C","GB"], ["CN", domain]] )
    csr.public_key = key.public_key
    csr.sign( key, OpenSSL::Digest::SHA1.new )

    # And then the certificate
    crt            = OpenSSL::X509::Certificate.new
    crt.subject    = csr.subject

    #
    # Theoretically we could use a CA to sign the cert.
    #
    if ca_cert.nil? or ca_key.nil?
      warn "Not setting the issuer as the CA because the CA key is not set" if !ca_cert.nil? and ca_key.nil?
      crt.issuer    = csr.subject
    else
      crt.issuer   = ca_cert.subject
    end
    crt.public_key = csr.public_key
    crt.not_before = Time.now
    crt.not_after  = Time.now + 60
    #
    # Make sure we increment the serial for each regeneration, to make sure
    # there are differences when regenerating a certificate for a new domain.
    #
    crt.serial     = @@serial
    @@serial += 1
    crt.version    = 1 

    if ca_cert.nil? or ca_key.nil?
      warn "Not signing certificate with CA key because the CA certificate is not set" if ca_cert.nil? and !ca_key.nil?
      crt.sign( key, OpenSSL::Digest::SHA1.new )  
    else
      crt.sign( ca_key, OpenSSL::Digest::SHA1.new )
    end

    crt
  end

  #
  # Returns a key and certificate
  #
  def do_generate_key_and_crt(domain, ca_cert=nil, ca_key=nil)
    key = do_generate_key
    return [key, do_generate_crt(domain, key, ca_cert, ca_key)]
  end

  ####
  #
  # Tests start here.
  #
  #####

  def test_ssl_enabled?
    #
    # This should return true if an IP has been set, and we can find a matching key and cert.
    #
    # Initially no IP or key / cert have been configured.
    #
    assert( !@domain.ssl_enabled? )

    #
    # Now set an IP.  This should still return false.
    #
    ip = "80.68.88.52"
    File.open(@domain.directory+"/config/ip","w+"){|fh| fh.puts ip}
    assert( !@domain.ssl_enabled? )

    #
    # Generate a key + cert.  It should now return true.
    #
    key, crt = do_generate_key_and_crt(@domain.name)
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+key.to_pem}
    assert( @domain.ssl_enabled? )
  end

  def test_ssl_mandatory?
    #
    # First make sure this responds "false" 
    #
    assert( !@domain.ssl_mandatory? )

    #
    # Now it should return true
    #
    FileUtils.touch(@domain.directory+"/config/ssl-only")
    assert( @domain.ssl_mandatory? )
  end

  def test_ssl_x509_certificate
    #
    # Generate a key 
    #
    key, crt = do_generate_key_and_crt(@domain.name)

    #
    # Return nil if no certificate filename has been set
    #
    assert_nil(@domain.ssl_x509_certificate)

    #
    # Now write the file
    #
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+key.to_pem}
    @domain.ssl_x509_certificate_file = @domain.directory+"/config/ssl.combined"

    #
    # Now it should read back the combined file correctly
    #
    assert_kind_of(crt.class, @domain.ssl_x509_certificate)
    assert_equal(crt.to_der, @domain.ssl_x509_certificate.to_der)

    #
    # Generate a new certificate
    #
    key, crt = do_generate_key_and_crt(@domain.name)
    #
    # Make sure it doesn't match the last one
    #
    assert_not_equal(crt.to_der, @domain.ssl_x509_certificate.to_der)

    File.open(@domain.directory+"/config/ssl.crt","w+"){|fh| fh.write crt.to_pem}
    @domain.ssl_x509_certificate_file = @domain.directory+"/config/ssl.crt"
    #
    # Now it should read back the individual file correctly
    #
    assert_equal(crt.to_der, @domain.ssl_x509_certificate.to_der)
  end

  #
  # Sh
  #
  def test_ssl_key
    #
    # Generate a key and cert
    #
    key, crt = do_generate_key_and_crt(@domain.name)

    #
    # Return nil if no certificate filename has been set
    #
    assert_nil(@domain.ssl_key)

    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+key.to_pem}
    @domain.ssl_key_file = @domain.directory+"/config/ssl.combined"

    #
    # Now it should read back the combined file correctly
    #
    assert_kind_of(key.class, @domain.ssl_key)
    assert_equal(key.to_der, @domain.ssl_key.to_der)

    #
    # Generate a new key
    #
    key = do_generate_key

    #
    # Make sure it doesn't match the last one
    #
    assert_not_equal(key.to_der, @domain.ssl_key.to_der)

    File.open(@domain.directory+"/config/ssl.key","w+"){|fh| fh.write key.to_pem}
    @domain.ssl_key_file = @domain.directory+"/config/ssl.key"

    assert_equal(key.to_der, @domain.ssl_key.to_der)
  end

  def test_ssl_available_certificate_files
    #
    # Generate a key and cert
    #
    key, crt = do_generate_key_and_crt(@domain.name)

    #
    # Write the certificate in various forms
    #
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+key.to_pem}
    File.open(@domain.directory+"/config/ssl.key","w+"){|fh| fh.write crt.to_pem+key.to_pem}
    File.open(@domain.directory+"/config/ssl.crt","w+"){|fh| fh.write crt.to_pem}
    File.open(@domain.directory+"/config/ssl.cert","w+"){|fh| fh.write crt.to_pem}
    File.open(@domain.directory+"/config/ssl.pem","w+"){|fh| fh.write crt.to_pem}

    #
    # Combined is preferred
    #
    assert_equal( %w(combined key crt cert pem).collect{|ext| @domain.directory+"/config/ssl."+ext}, 
                   @domain.ssl_available_certificate_files)

    #
    # If a combined file contains a non-matching cert+key, don't return it
    #
    new_key = do_generate_key
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem + new_key.to_pem}

    assert_equal( %w(key crt cert pem).collect{|ext| @domain.directory+"/config/ssl."+ext},
                  @domain.ssl_available_certificate_files )
  end

  def test_ssl_available_key_files
    #
    # Generate a key and cert
    #
    key, crt = do_generate_key_and_crt(@domain.name)

    #
    # Write the key to a number of files
    #
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+key.to_pem}
    File.open(@domain.directory+"/config/ssl.key","w+"){|fh| fh.write key.to_pem}
    File.open(@domain.directory+"/config/ssl.crt","w+"){|fh| fh.write crt.to_pem}

    #
    # Combined is preferred
    #
    assert_equal( %w(combined key).collect{|ext| @domain.directory+"/config/ssl."+ext}, 
                  @domain.ssl_available_key_files )

    #
    # If a combined file contains a non-matching cert+key, don't return it
    #
    new_key = do_generate_key
    assert(!crt.check_private_key(new_key))

    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem + new_key.to_pem}

    assert_equal( [@domain.directory+"/config/ssl.key"], 
                  @domain.ssl_available_key_files )
  end

  def test_ssl_find_matching_certificate_and_key
    #
    # Generate a key and cert
    #
    key, crt = do_generate_key_and_crt(@domain.name)

    #
    # If no key and cert are found, nil is returned.
    #
    assert_nil( @domain.ssl_find_matching_certificate_and_key )

    #
    # Initially, the combined cert should contain both the certificate and the key
    #
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+key.to_pem}
    File.open(@domain.directory+"/config/ssl.key","w+"){|fh| fh.write crt.to_pem+key.to_pem}
    assert_equal( [@domain.directory+"/config/ssl.combined"]*2, 
                  @domain.ssl_find_matching_certificate_and_key )

    #
    # Now delete that file, and see what comes out.  We expect the key to be first now.
    #
    FileUtils.rm_f(@domain.directory+"/config/ssl.combined")
    assert_equal( [@domain.directory+"/config/ssl.key"]*2,
                  @domain.ssl_find_matching_certificate_and_key )

    #
    # Now recreate a key which is only a key, and see if we get the correct cert returned.
    #
    File.open(@domain.directory+"/config/ssl.key","w+"){|fh| fh.write key.to_pem}
    File.open(@domain.directory+"/config/ssl.crt","w+"){|fh| fh.write crt.to_pem}
    assert_equal( [@domain.directory+"/config/ssl.crt", @domain.directory+"/config/ssl.key"], 
                  @domain.ssl_find_matching_certificate_and_key )

    #
    # Now generate a new key, and corrupt the combined certificate.
    # find_matching_certificate_and_key should now return the separate,
    # matching key and cert.
    #
    new_key = do_generate_key
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem + new_key.to_pem}
    assert_equal( [@domain.directory+"/config/ssl.crt", @domain.directory+"/config/ssl.key"],
                  @domain.ssl_find_matching_certificate_and_key )

    #
    # Now remove the crt file, leaving the duff combined cert, and the other
    # key.  This should return nil, since the combined file contains the
    # certificate that matches the *separate* key, and a non-matching key,
    # rendering it useless.
    #
    FileUtils.rm_f(@domain.directory+"/config/ssl.crt")
    assert_nil(@domain.ssl_find_matching_certificate_and_key)

  end


  #################################
  #
  # The following methods are not explicitly tested:
  #    ssl_certificate_chain_file
  #    ssl_add_ca_path(path)
  #    ssl_certificate_store
  #
  # since they're all done as part of the verification tests below.
  #

  def test_ssl_verify_self_signed
    #
    # Generate a key and cert
    #
    key, crt = do_generate_key_and_crt(@domain.name)

    #
    # Write a combined cert
    #
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+key.to_pem}

    #
    # Now make sure it verifies OK
    #
    assert_nothing_raised{ @domain.ssl_x509_certificate_file = @domain.directory+"/config/ssl.combined" }
    assert_nothing_raised{ @domain.ssl_key_file         = @domain.directory+"/config/ssl.combined" }

    #
    # This should verify.
    #
    assert_nothing_raised{ @domain.ssl_verify }

    #
    # Generate another key
    #
    new_key = do_generate_key

    #
    # Now write a combined cert with this new key.  This should not verify.
    #
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+new_key.to_pem}
    assert_raise(OpenSSL::X509::CertificateError){ @domain.ssl_verify }

    #
    # Now sign the certificate with this new key.  This should cause the verification to fail.
    #
    crt.sign( new_key, OpenSSL::Digest::SHA1.new )
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+key.to_pem}
    assert_raise(OpenSSL::X509::CertificateError){ @domain.ssl_verify }

    #
    # Now write a combined cert with the new key.  This should still not
    # verify, as the public key on the certificate will not match the private
    # key, even though we've signed the cert with this new private key.
    #
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+new_key.to_pem}
    assert_raise(OpenSSL::X509::CertificateError){ @domain.ssl_verify }
  end

  def test_ssl_verify_with_root_ca
    #
    # Use our intermediate CA.
    #
    ca_cert = OpenSSL::X509::Certificate.new(File.read("RootCA/RootCA.crt"))
    ca_key  = OpenSSL::PKey::RSA.new(File.read("RootCA/RootCA.key"))

    #
    # Add the Root CA path
    # 
    @domain.ssl_add_ca_path("./RootCA/")

    #
    # Generate a key and cert
    #
    key = do_generate_key
    crt = do_generate_crt(@domain.name, key, ca_cert, ca_key)

    #
    # Write a combined cert
    #
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+key.to_pem}

    #
    # This should verify just fine.
    #
    assert_nothing_raised{ @domain.ssl_x509_certificate_file = @domain.directory+"/config/ssl.combined" }
    assert_nothing_raised{ @domain.ssl_key_file         = @domain.directory+"/config/ssl.combined" }
    assert_nothing_raised{ @domain.ssl_verify }
  end

  def test_ssl_verify_with_intermediate_ca
    #
    # Use our intermediate CA.
    #
    ca_cert = OpenSSL::X509::Certificate.new(File.read("IntermediateCA/IntermediateCA.crt"))
    ca_key  = OpenSSL::PKey::RSA.new(File.read("IntermediateCA/IntermediateCA.key"))

    #
    # Add the Root CA path
    # 
    @domain.ssl_add_ca_path("./RootCA/")

    #
    # Generate a key and cert
    #
    key = do_generate_key
    crt = do_generate_crt(@domain.name, key, ca_cert, ca_key)

    #
    # Write a combined cert
    #
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+key.to_pem}

    #
    # This should not verify yet, as the bundle hasn't been copied in place.
    #
    assert_nothing_raised{ @domain.ssl_x509_certificate_file = @domain.directory+"/config/ssl.combined" }
    assert_nothing_raised{ @domain.ssl_key_file         = @domain.directory+"/config/ssl.combined" }
    assert_raise(OpenSSL::X509::CertificateError){ @domain.ssl_verify }

    #
    # Now copy the bundle in place
    #
    FileUtils.cp("IntermediateCA/IntermediateCA.crt",@domain.directory+"/config/ssl.bundle")

    #
    # Now it should verify just fine.
    #
    assert_nothing_raised{ @domain.ssl_verify }
  end

end
