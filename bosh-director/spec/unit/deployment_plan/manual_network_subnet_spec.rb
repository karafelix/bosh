require 'spec_helper'

describe 'Bosh::Director::DeploymentPlan::ManualNetworkSubnet' do
  before { @network = instance_double('Bosh::Director::DeploymentPlan::Network', :name => 'net_a') }
  let(:ip_provider_factory) { BD::DeploymentPlan::IpProviderFactory.new(logger, cloud_config: true) }

  def make_subnet(properties, availability_zones)
    BD::DeploymentPlan::ManualNetworkSubnet.new(@network, properties, availability_zones, reserved_ranges, ip_provider_factory)
  end

  let(:reserved_ranges) { [] }
  let(:instance) { instance_double(BD::DeploymentPlan::Instance, model: BD::Models::Instance.make) }

  def create_static_reservation(ip)
    BD::StaticNetworkReservation.new(instance, @network, NetAddr::CIDR.create(ip))
  end

  def create_dynamic_reservation(ip)
    reservation = BD::DynamicNetworkReservation.new(instance, @network)
    reservation.resolve_ip(NetAddr::CIDR.create(ip))
    reservation
  end

  describe :initialize do
    it 'should create a subnet spec' do
      subnet = make_subnet(
        {
          'range' => '192.168.0.0/24',
          'gateway' => '192.168.0.254',
          'cloud_properties' => {'foo' => 'bar'}
        },
        [],
      )

      expect(subnet.range.ip).to eq('192.168.0.0')
      subnet.range.ip.size == 255
      expect(subnet.netmask).to eq('255.255.255.0')
      expect(subnet.gateway).to eq('192.168.0.254')
      expect(subnet.dns).to eq(nil)
    end

    it 'should require a range' do
      expect {
        make_subnet(
          {
            'cloud_properties' => {'foo' => 'bar'},
            'gateway' => '192.168.0.254',
          },
          []
        )
      }.to raise_error(BD::ValidationMissingField)
    end

    context "gateway property" do
      it "should require a gateway" do
        expect {
          make_subnet(
            {
              "range" => "192.168.0.0/24",
              "cloud_properties" => {"foo" => "bar"},
            }, []
          )
        }.to raise_error(BD::ValidationMissingField)
      end

      context "when the gateway is configured to be optional" do
        it "should not require a gateway" do
          allow(Bosh::Director::Config).to receive(:ignore_missing_gateway).and_return(true)

          expect {
            make_subnet(
              {
                "range" => "192.168.0.0/24",
                "cloud_properties" => {"foo" => "bar"},
              },
              []
            )
          }.to_not raise_error
        end
      end
    end

    it 'default cloud properties to empty hash' do
      subnet = make_subnet(
        {

          'range' => '192.168.0.0/24',
          'gateway' => '192.168.0.254',
        },
        []
      )
      expect(subnet.cloud_properties).to eq({})
    end

    it 'should allow a gateway' do
      subnet = make_subnet(
        {
          'range' => '192.168.0.0/24',
          'gateway' => '192.168.0.254',
          'cloud_properties' => {'foo' => 'bar'}
        },
        []
      )

      expect(subnet.gateway.ip).to eq('192.168.0.254')
    end

    it 'should make sure gateway is a single ip' do
      expect {
        make_subnet(
          {
            'range' => '192.168.0.0/24',
            'gateway' => '192.168.0.254/30',
            'cloud_properties' => {'foo' => 'bar'}
          },
          []
        )
      }.to raise_error(BD::NetworkInvalidGateway,
          /must be a single IP/)
    end

    it 'should make sure gateway is inside the subnet' do
      expect {
        make_subnet(
          {
            'range' => '192.168.0.0/24',
            'gateway' => '190.168.0.254',
            'cloud_properties' => {'foo' => 'bar'}
          },
          []
        )
      }.to raise_error(BD::NetworkInvalidGateway,
          /must be inside the range/)
    end

    it 'should make sure gateway is not the network id' do
      expect {
        make_subnet(
          {
            'range' => '192.168.0.0/24',
            'gateway' => '192.168.0.0',
            'cloud_properties' => {'foo' => 'bar'}
          },
          []
        )
      }.to raise_error(Bosh::Director::NetworkInvalidGateway,
          /can't be the network id/)
    end

    it 'should make sure gateway is not the broadcast IP' do
      expect {
        make_subnet(
          {
            'range' => '192.168.0.0/24',
            'gateway' => '192.168.0.255',
            'cloud_properties' => {'foo' => 'bar'}
          },
          []
        )
      }.to raise_error(Bosh::Director::NetworkInvalidGateway,
          /can't be the broadcast IP/)
    end

    it 'should allow DNS servers' do
      subnet = make_subnet(
        {
          'range' => '192.168.0.0/24',
          'dns' => %w(1.2.3.4 5.6.7.8),
          'gateway' => '192.168.0.254',
          'cloud_properties' => {'foo' => 'bar'}
        },
        []
      )

      expect(subnet.dns).to eq(%w(1.2.3.4 5.6.7.8))
    end

    it 'should fail when reserved range is not valid' do
      expect {
        make_subnet(
          {
            'range' => '192.168.0.0/24',
            'reserved' => '192.167.0.5 - 192.168.0.10',
            'gateway' => '192.168.0.254',
            'cloud_properties' => {'foo' => 'bar'}
          },
          []
        )
      }.to raise_error(Bosh::Director::NetworkReservedIpOutOfRange,
          "Reserved IP `192.167.0.5' is out of " +
            "network `net_a' range")
    end

    it 'should fail when the static IP is not valid' do
      expect {
        make_subnet(
          {
            'range' => '192.168.0.0/24',
            'static' => '192.167.0.5 - 192.168.0.10',
            'gateway' => '192.168.0.254',
            'cloud_properties' => {'foo' => 'bar'}
          },
          []
        )
      }.to raise_error(Bosh::Director::NetworkStaticIpOutOfRange,
          "Static IP `192.167.0.5' is out of " +
            "network `net_a' range")
    end

    it 'should fail when the static IP is in reserved range' do
      expect {
        make_subnet(
          {
            'range' => '192.168.0.0/24',
            'reserved' => '192.168.0.5 - 192.168.0.10',
            'static' => '192.168.0.5',
            'gateway' => '192.168.0.254',
            'cloud_properties' => {'foo' => 'bar'}
          },
          []
        )
      }.to raise_error(Bosh::Director::NetworkStaticIpOutOfRange,
          "Static IP `192.168.0.5' is out of " +
            "network `net_a' range")
    end

    describe 'availability zone' do
      context 'with no availability zone specified' do
        it 'does not care whether that az name is in the list' do
          expect {
            make_subnet(
              {
                'range' => '192.168.0.0/24',
                'gateway' => '192.168.0.254',
                'cloud_properties' => {'foo' => 'bar'},
              },
              []
            )
          }.to_not raise_error
        end
      end

      context 'with a nil availability zone' do
        it 'errors' do
          expect {
            make_subnet(
              {
                'range' => '192.168.0.0/24',
                'gateway' => '192.168.0.254',
                'cloud_properties' => {'foo' => 'bar'},
                'availability_zone' => nil
              },
              [instance_double(Bosh::Director::DeploymentPlan::AvailabilityZone)]
            )
          }.to raise_error(BD::ValidationInvalidType)
        end
      end

      context 'with an availability zone that is present' do
        it 'is valid' do
          expect {
            make_subnet(
              {
                'range' => '192.168.0.0/24',
                'gateway' => '192.168.0.254',
                'cloud_properties' => {'foo' => 'bar'},
                'availability_zone' => 'foo'
              },
              [
                instance_double(Bosh::Director::DeploymentPlan::AvailabilityZone, name: 'bar'),
                instance_double(Bosh::Director::DeploymentPlan::AvailabilityZone, name: 'foo'),
              ]
            )
          }.to_not raise_error
        end
      end

      context 'with an availability zone that is not present' do
        it 'errors' do
          expect {
            make_subnet(
              {
                'range' => '192.168.0.0/24',
                'gateway' => '192.168.0.254',
                'cloud_properties' => {'foo' => 'bar'},
                'availability_zone' => 'foo'
              },
              [
                instance_double(Bosh::Director::DeploymentPlan::AvailabilityZone, name: 'bar'),
              ]
            )          }.to raise_error(Bosh::Director::NetworkSubnetUnknownAvailabilityZone, "Network 'net_a' refers to an unknown availability zone 'foo'")
        end
      end

    end
  end

  describe :overlaps? do
    before(:each) do
      @subnet = make_subnet(
        {
          'range' => '192.168.0.0/24',
          'gateway' => '192.168.0.254',
          'cloud_properties' => {'foo' => 'bar'},
        },
        []
      )
    end

    it 'should return false when the given range does not overlap' do
      other = make_subnet(
        {
          'range' => '192.168.1.0/24',
          'gateway' => '192.168.1.254',
          'cloud_properties' => {'foo' => 'bar'},
        },
        []
      )
      expect(@subnet.overlaps?(other)).to eq(false)
    end

    it 'should return true when the given range overlaps' do
      other = make_subnet(
        {
          'range' => '192.168.0.128/28',
          'gateway' => '192.168.0.142',
          'cloud_properties' => {'foo' => 'bar'},
        },
        []
      )
      expect(@subnet.overlaps?(other)).to eq(true)
    end
  end
end